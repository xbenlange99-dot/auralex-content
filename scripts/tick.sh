#!/usr/bin/env bash
# Auralex Content Publisher – Tick-Skript, laeuft taeglich um 07:00 via launchd.
# Liest posts/*.md mit status: ready, prueft Duplikate in Metricool, plant sie
# via Metricool-MCP ein, setzt status: scheduled und pusht JEDEN Post einzeln
# zurueck (verhindert Doppel-Postings bei einem Crash mitten im Lauf).
# Postet je nach "channels" auf Facebook und/oder Instagram, jeweils als
# Feed-Post/Reel PLUS zusaetzlich als Story (seit 2026-07-15, best-effort,
# s. Schritt b2 im Prompt unten).
#
# EINE Metricool-Brand: Auralex (Firma), channels facebook/instagram,
# Blog-Id $AURALEX_BLOG_ID.
# Bis 30.07.2026 gab es hier eine zweite Brand fuer "David Schnell (Personal
# Brand)" mit tiktok/linkedin und $DAVID_BLOG_ID. Ben hat entschieden: Davids
# Personal Brand wird nicht bespielt. Die Logik ist ersatzlos ausgebaut, ein
# Post mit tiktok/linkedin in "channels" ist jetzt ein Konfigurationsfehler.
# Rueckholbar ueber die git-Historie (Commit "Davids Personal Brand ausgebaut").
#
# Reliability-Fixes (aus der Helal-Produktion uebernommen):
#  - launchd hat ein minimales PATH -> claude-Pfad und PATH explizit setzen.
#  - Das Metricool-MCP ist im $HOME-Scope konfiguriert -> claude MUSS mit
#    cwd=$HOME gestartet werden, sonst wird das MCP nicht geladen.
#  - Lockfile verhindert ueberlappende Laeufe, z. B. wenn der taegliche
#    Lauf sich mit einem manuellen posten.command-Aufruf ueberschneidet
#    oder ein Lauf haengen bleibt.
#  - git pull passiert VOR dem Claude-Aufruf als expliziter, laut
#    fehlschlagender Schritt (kein stiller Fehlschlag).

set -uo pipefail

export HOME="/Users/bl"
export PATH="/Users/bl/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
CLAUDE="/Users/bl/.local/bin/claude"
REPO="/Users/bl/Arbeit/Auralex/content"
LOG="$REPO/out/tick.log"
LOCKDIR="$REPO/.tick.lock"

mkdir -p "$(dirname "$LOG")"
echo "=== $(date) ===" >> "$LOG"

# --- Sichtbarer Alarm bei Fehlschlag (Trap, deckt JEDEN Ausstieg ab) ---
# Bis 01.08.2026 scheiterte der Lauf still: launchd wertet den Rueckgabewert
# nicht aus, und niemand liest tick.log praeventiv. Zwei Ausfaelle (gesperrter
# Claude-Zugang, toter Pfad nach dem Umzug) blieben so tagelang unbemerkt.
# Der Trap sitzt bewusst VOR allen Pruefungen, damit auch ein frueher Abbruch
# (claude fehlt, git-Konflikt, blogId fehlt) sichtbar wird.
STATUSDATEI="$REPO/out/LETZTER-LAUF.txt"
LOCK_GESETZT=0   # nur der Lauf, der das Lock gesetzt hat, raeumt es wieder ab
abschluss() {
  RC=$?
  [ "$LOCK_GESETZT" -eq 1 ] && rmdir "$LOCKDIR" 2>/dev/null
  if [ "$RC" -ne 0 ]; then
    GRUND=$(grep -iE 'fehler|error|disabled|denied|failed|refused' "$LOG" | tail -1 | cut -c1-200)
    {
      echo "FEHLGESCHLAGEN  $(date '+%Y-%m-%d %H:%M')  rc=$RC"
      echo "${GRUND:-kein Grund im Log gefunden}"
      echo "Vollstaendig: $LOG"
    } > "$STATUSDATEI"
    /usr/bin/osascript -e 'display notification "Posts wurden nicht eingeplant. Details: Auralex/content/out/LETZTER-LAUF.txt" with title "Auralex-Publisher fehlgeschlagen" sound name "Basso"' >/dev/null 2>&1
  else
    echo "OK  $(date '+%Y-%m-%d %H:%M')  ${READY_COUNT:-0} Post(s) verarbeitet" > "$STATUSDATEI"
  fi
}
trap abschluss EXIT

if [ ! -x "$CLAUDE" ]; then
  echo "FEHLER: claude nicht gefunden/ausfuehrbar unter $CLAUDE" >> "$LOG"
  exit 1
fi

# --- Lock: verhindert ueberlappende Ticks ---
if [ -d "$LOCKDIR" ]; then
  LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCKDIR" 2>/dev/null || echo 0) ))
  if [ "$LOCK_AGE" -lt 1800 ]; then
    echo "Vorheriger Lauf noch aktiv (Lock < 30 Min alt) - ueberspringe diesen Tick." >> "$LOG"
    exit 0
  fi
  echo "Alter Lock (> 30 Min) gefunden, vermutlich abgestuerzter Lauf - entferne ihn." >> "$LOG"
  rmdir "$LOCKDIR" 2>/dev/null
fi
mkdir "$LOCKDIR" || { echo "Konnte Lock nicht setzen - ueberspringe." >> "$LOG"; exit 0; }
LOCK_GESETZT=1   # ab hier raeumt der EXIT-Trap das Lock wieder ab

# --- git pull: expliziter, sichtbarer Schritt ---
cd "$REPO" || exit 1
if ! git pull --ff-only >> "$LOG" 2>&1; then
  echo "FEHLER: git pull --ff-only fehlgeschlagen (Konflikt / lokale Aenderungen?). Breche ab, KEINE Posts werden verarbeitet." >> "$LOG"
  exit 1
fi

# Nur die Frontmatter (zwischen den ersten beiden "---"-Zeilen) pruefen, nie
# den Caption-Text -- sonst wuerde ein Post, dessen Bildtext zufaellig mit
# "status: ready" beginnt, faelschlich als bereit erkannt.
READY_COUNT=0
for f in "$REPO"/posts/*.md; do
  [ -f "$f" ] || continue
  if awk '/^---$/{n++; next} n==1' "$f" | grep -qx "status: ready"; then
    READY_COUNT=$((READY_COUNT + 1))
  fi
done
echo "Gefundene Posts mit status: ready = $READY_COUNT" >> "$LOG"
if [ "$READY_COUNT" -eq 0 ]; then
  echo "Nichts zu tun." >> "$LOG"
  exit 0
fi

if [ -z "${AURALEX_BLOG_ID:-}" ]; then
  echo "FEHLER: AURALEX_BLOG_ID ist nicht gesetzt, aber $READY_COUNT Post(s) warten. Siehe Setup-Checkliste (blogId per mcp__metricool__getBrands ermitteln, in der launchd-plist eintragen)." >> "$LOG"
  exit 1
fi

PROMPTFILE="$REPO/out/tick-prompt.txt"
JETZT=$(date '+%Y-%m-%dT%H:%M:%S')   # fuer die Zeitpunkt-Pruefung im Prompt (Schritt 0b)
cat > "$PROMPTFILE" <<PROMPT_EOF
Du verwaltest die automatische Auralex-Social-Media-Warteschlange im Repo
${REPO} ueber das Metricool-MCP. Es gibt genau EINE Metricool-Brand in dieser
Pipeline: Auralex (Firma), Netzwerke facebook/instagram, blogId
${AURALEX_BLOG_ID}.

WICHTIG: Nutze fuer ALLE Git-Befehle die Form
  git -C ${REPO} befehl
und niemals "cd && git ...", damit jeder Bash-Aufruf sauber mit "git" beginnt.

Schritte:

1) Lies alle Dateien in ${REPO}/posts/*.md.
   Parse das YAML-Frontmatter (id, status, format, channels, publish_at, assets)
   und den Caption-Text (alles nach dem zweiten "---").

2) Bearbeite NUR Posts mit status: ready. Ignoriere draft, scheduled, error.
   Wenn keiner status: ready hat, gib {"ok":true,"processed":[]} aus und stoppe.

3) Verarbeite jeden ready-Post EINZELN, nacheinander (nicht parallel), in
   dieser Reihenfolge: nach publish_at aufsteigend sortiert.

   Fuer jeden Post:

   0) Kanal-Pruefung (VOR jedem Tool-Call fuer diesen Post):
      - channels enthaelt ausschliesslich facebook und/oder instagram
        -> blogId = ${AURALEX_BLOG_ID}. Weiter mit (a).
      - Jeder andere Fall (ein Netzwerk-Wert ist unbekannt oder gehoert nicht
        zu Auralex, z. B. tiktok oder linkedin): das ist ein
        Konfigurationsfehler, kein Tool-Call. Setze status auf "error" mit
        einer kurzen Begruendung im Bash-Log, committe/pushe (siehe c), und
        mach mit dem naechsten Post weiter.

   0b) Zeitpunkt-Pruefung (nach Schritt 0, VOR Schritt a):
      Davids Generator setzt publish_at auf die Erzeugungszeit des Posts. Der
      Tick laeuft aber nur einmal taeglich um 07:00. Jeder Post, der nach 07:00
      entsteht, hat beim naechsten Lauf ein publish_at in der Vergangenheit --
      Metricool lehnt das hart ab und der Post landet in status: error. Das ist
      eine Folge des Taktes, kein Redaktionsfehler, und darf den Post nicht
      verbrennen.

      Aktuelle Zeit beim Start dieses Laufs: ${JETZT} (Europe/Berlin).
      Rechne ausschliesslich damit -- du hast kein Werkzeug, um die Uhr selbst
      abzufragen. Wenn publish_at weniger als 60 Minuten danach liegt,
      verschiebe:
      - Nennt der Caption-Text oder ein Hashtag einen Wochentag (Montag bis
        Sonntag, auch "Samstagsfrage" o. ae.)? Dann in Schritten von 7 Tagen
        verschieben, bis der Zeitpunkt mehr als 60 Minuten in der Zukunft
        liegt -- sonst stimmt die Aussage des Posts nicht mehr zum Tag.
      - Sonst in Schritten von 1 Tag verschieben, bis derselbe Abstand erreicht
        ist. Uhrzeit in beiden Faellen unveraendert lassen.
      Das neue publish_at wird in Schritt (c) zusammen mit dem Status in die
      Datei geschrieben (ein Commit), und die Verschiebung kommt in das
      "detail"-Feld des Abschlussberichts ("publish_at 01.08. 12:08 -> 02.08.
      12:08, Takt").

   a) Sicherheitscheck vor dem Planen: rufe mcp__metricool__getScheduledPosts
      auf mit einem Zeitfenster von publish_at minus 3 Stunden bis publish_at
      plus 3 Stunden (blogId = die in Schritt 0 bestimmte Id, timezone
      Europe/Berlin). Wenn dort bereits ein Post mit den ersten ~40 Zeichen
      eines nahezu identischen Texts existiert: gehe davon aus, dass ein
      vorheriger Tick das Scheduling bereits erfolgreich durchgefuehrt hat,
      aber der Status-Commit fehlgeschlagen ist. Plane NICHT erneut, sondern
      springe direkt zu Schritt (c) fuer diesen Post.

   b) Andernfalls rufe mcp__metricool__createScheduledPost auf mit:
      - blog_id: die in Schritt 0 bestimmte blogId
      - date: publish_at ohne Zeitzonen-Suffix, Format YYYY-MM-DDTHH:MM:SS
      - info.text: der Caption-Body aus der Markdown-Datei (unveraendert!).
      - info.media: fuer jeden Dateinamen in "assets" die URL
        https://raw.githubusercontent.com/xbenlange99-dot/auralex-content/main/assets/<id>/<dateiname>
        in der Reihenfolge der Liste (Reihenfolge = Karussell-Reihenfolge).
      - info.providers: ein Eintrag pro Netzwerk in "channels", also
        {"network":"facebook"} und/oder {"network":"instagram"}
      - info.publicationDate: {"dateTime": publish_at ohne Offset, "timezone":"Europe/Berlin"}
      - info.autoPublish: true, info.draft: false, info.shortener: false
      - info.instagramData: {"type":"POST","tags":[]}  (nur wenn instagram in channels)
      - info.facebookData: {"type":"POST","title":""}
        (nur wenn facebook in channels; KEIN "boost"-Feld setzen -- die
        Metricool-API akzeptiert dort nur Werte >2.0 und lehnt boost:0 ab,
        also das Feld bei unbeworbenen Posts einfach weglassen)
      - SONDERFALL format: video (Reel): "assets" enthaelt genau
        EINE mp4-Datei, info.media ist dann diese eine mp4-URL (gleiches
        raw.githubusercontent-Schema).
        - facebook in channels: info.facebookData: {"type":"REEL","title":""}
          statt POST.
        - instagram in channels: info.instagramData: {"type":"REEL","tags":[]}
          statt POST.
        Schlaegt der Aufruf mit einem Typ-Fehler fehl, versuche es EINMAL
        erneut mit {"type":"POST","title":""} bzw. {"type":"POST","tags":[]}
        (Video-Post statt Reel), bevor du den Post auf error setzt.
      Wenn der Aufruf fehlschlaegt: setze status auf "error" statt "scheduled",
      committe/pushe trotzdem (siehe c), und fahre mit dem NAECHSTEN Post fort.
      Erfinde KEINE erfolgreiche Planung, wenn der Tool-Call einen Fehler
      zurueckgab.

   b2) ZUSAETZLICH zu (b) -- Story-Version (seit 2026-07-15, David-Wunsch:
      jeder Auralex-Post soll auf Facebook UND Instagram als Feed-Post/Reel
      PLUS als Story laufen).

      Nur ausfuehren, wenn (b) selbst erfolgreich war (Status
      wuerde "scheduled") ODER (a) den Post als bereits geplant erkannt hat --
      NIE nach einem echten Fehlschlag von (b).

      Pruefe zuerst per mcp__metricool__getScheduledPosts im selben
      Zeitfenster wie (a), ob dort schon ein Eintrag existiert, dessen
      facebookData.type bzw. instagramData.type "STORY" ist und dessen Medium
      zu diesem Post passt (Retry-Fall, z.B. nach einem Status-Commit-Crash).
      Falls ja: ueberspringen, nicht doppelt anlegen.

      Sonst: rufe mcp__metricool__createScheduledPost ERNEUT auf, mit exakt
      denselben Feldern wie in (b)/dem Sonderfall (blog_id, date, info.media,
      info.providers, info.publicationDate, info.autoPublish, info.draft,
      info.shortener), aber:
      - info.text: "" (leerer String -- Storys zeigen ohnehin keinen
        Caption-Text, und ein leerer Text verhindert, dass dieser
        Story-Aufruf beim naechsten Tick faelschlich ueber den
        Text-Abgleich aus (a) als "Haupt-Post schon geplant" erkannt wird)
      - info.facebookData: {"type":"STORY"} statt POST/REEL (nur wenn
        facebook in channels)
      - info.instagramData: {"type":"STORY","tags":[]} statt POST/REEL (nur
        wenn instagram in channels)

      Dieser Story-Aufruf ist BEST-EFFORT und blockiert NICHTS: schlaegt er
      fehl (z.B. weil die Metricool-API "STORY" als Typ nicht akzeptiert),
      setze NICHT den Status der Datei auf "error" deswegen -- der
      Haupt-Post aus (b) ist bereits sicher geplant, das hier ist nur der
      Zusatzkanal. Schreib stattdessen exakt eine Zeile in dein Bash-Log
      ("STORY-FEHLER <id>: <kurzer Grund>") und mach normal mit (c) weiter.
      Erfinde auch hier KEINEN Erfolg, wenn der Tool-Call einen Fehler
      zurueckgab.

   c) SOFORT nach Schritt 0/(a)/(b)/(b2) fuer DIESEN Post (ausser beim
      SKIP-Fall aus Schritt 0 -- der aendert an der Datei nichts und committet
      auch nichts): bearbeite im Frontmatter dieser einen Datei die
      status-Zeile (ready -> scheduled, oder ready -> error bei Fehlschlag)
      und, falls Schritt 0b eine Verschiebung ergeben hat, die
      publish_at-Zeile. Aendere sonst NICHTS an der Datei, insbesondere nicht
      den Caption-Text. Dann:
        git -C ${REPO} add posts/<datei>.md
        git -C ${REPO} commit -m "chore: <id> -> scheduled"
        git -C ${REPO} push
      Erst wenn Commit+Push fuer DIESEN Post erfolgreich waren, gehe zum
      naechsten Post ueber. Wenn push fehlschlaegt (z.B. weil David
      inzwischen etwas gepusht hat): fuehre
      "git -C ${REPO} pull --rebase" aus und versuche push einmal erneut.
      Wenn es weiterhin fehlschlaegt, brich die Verarbeitung ab und melde den
      Fehler im Abschlussbericht.

4) Gib am Ende AUSSCHLIESSLICH ein JSON-Objekt aus (keinen weiteren Text):
   {"ok": true|false, "processed": [{"id":"...", "status":"scheduled"|"error"|"skipped", "detail":"..."}]}
PROMPT_EOF

cd "$REPO" || exit 1  # project-scope MCP (.mcp.json im Repo) statt frueher HOME-Scope
"$CLAUDE" -p "$(cat "$PROMPTFILE")" \
  --dangerously-skip-permissions \
  --allowedTools "Read" "Edit" "Bash(git:*)" \
                 "mcp__metricool__getScheduledPosts" "mcp__metricool__createScheduledPost" \
  >> "$LOG" 2>&1
RC=$?

echo "--- fertig (rc=$RC) $(date) ---" >> "$LOG"
exit $RC   # Statusdatei und Benachrichtigung erledigt der EXIT-Trap
