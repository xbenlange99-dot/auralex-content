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
#  - Das Metricool-MCP kommt aus der .mcp.json im Repo -> claude MUSS mit
#    cwd=$REPO gestartet werden, sonst wird das MCP nicht geladen.
#  - Die Sendetermine rechnet dieses Skript aus, nicht das Modell. Das Modell
#    bekommt eine fertige Tabelle (Schritt 0b im Prompt).
#  - Ein Lauf gilt nur als erfolgreich, wenn der Abschlussbericht das belegt --
#    claude beendet sich auch mit 0, wenn es die Arbeit verweigert hat.
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
  # 60 statt frueher 30 Minuten: seit dem Retry (s. unten) darf ein Lauf bis zu
  # drei Versuche mit je 120 s Pause brauchen, ohne dass ein nachfolgender Tick
  # das Lock faelschlich fuer verwaist haelt.
  if [ "$LOCK_AGE" -lt 3600 ]; then
    echo "Vorheriger Lauf noch aktiv (Lock < 60 Min alt) - ueberspringe diesen Tick." >> "$LOG"
    exit 0
  fi
  echo "Alter Lock (> 60 Min) gefunden, vermutlich abgestuerzter Lauf - entferne ihn." >> "$LOG"
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

# --- Ready-Posts finden und ihren Sendetermin bestimmen ---
#
# Nur die Frontmatter (zwischen den ersten beiden "---"-Zeilen) pruefen, nie
# den Caption-Text -- sonst wuerde ein Post, dessen Bildtext zufaellig mit
# "status: ready" beginnt, faelschlich als bereit erkannt.
#
# Die Terminrechnung passiert hier in der Shell und NICHT mehr im Prompt.
# Bis 02.08.2026 rechnete das Modell die Verschiebung in Prosa aus (frueher
# Schritt 0b). Datumsarithmetik ueber Monats- und Zeitumstellungsgrenzen ist
# nichts, was ein unbeaufsichtigter Job jede Nacht neu erwuerfeln sollte --
# ein Rechenfehler landet ungeprueft in Metricool. Das Modell bekommt jetzt
# eine fertige Tabelle und darf selbst nichts mehr ausrechnen.
#
# Die Uhrzeit ist immer Davids Uhrzeit. Verschoben wird nur der Tag, und nur
# so weit wie noetig: Davids Generator setzt publish_at auf die Erzeugungszeit,
# der Lauf ist aber einmal taeglich -- alles, was nach dem Lauf entsteht, hat
# am naechsten Morgen zwangslaeufig einen Zeitpunkt in der Vergangenheit.
# Nennt der Text einen Wochentag, wird in 7-Tage-Schritten verschoben, damit
# die Aussage des Posts zum Tag passt ("Samstagsfrage"); sonst taeglich.
#
# Gerechnet wird in Zivilzeit ("-v" VOR "-f", sonst schluckt date die
# Verschiebung stillschweigend), nicht in Sekunden: 7 Tage auf den 24.10. um
# 09:00 ergeben so den 31.10. um 09:00, waehrend reine Epoch-Arithmetik ueber
# die Zeitumstellung auf 08:00 verrutschen wuerde.

# --- Ein Arbeitsversuch: scannen, planen, pruefen ---------------------------
# Kapselung fuer den Retry weiter unten. Bewusst der GANZE Arbeitsteil und
# nicht nur der claude-Aufruf: ein halb durchgelaufener Versuch stellt Posts
# schon auf "scheduled" und committet sie. Ein zweiter Versuch muss deshalb
# Plantabelle UND READY_COUNT neu bilden, sonst schlaegt die Pruefung
# "Bericht deckt N von M ab" grundlos an. Der Funktionsrumpf ist absichtlich
# nicht eingerueckt -- das Prompt-Heredoc weiter unten geht 1:1 an das Modell.
WIEDERHOLBAR=0        # setzt versuch(): 1 = transienter Fehler, erneut versuchen
versuch() {
WIEDERHOLBAR=0
VORLAUF_SEK=3600      # Mindestabstand zwischen Lauf und Sendetermin
JETZT_SEK=$(date +%s)
READY_COUNT=0
PLANTABELLE=""

for f in "$REPO"/posts/*.md; do
  [ -f "$f" ] || continue
  awk '/^---$/{n++; next} n==1' "$f" | grep -qx "status: ready" || continue
  READY_COUNT=$((READY_COUNT + 1))

  DATEI=$(basename "$f")
  PID="${DATEI%.md}"
  ROH=$(awk '/^---$/{n++; next} n==1' "$f" | sed -n 's/^publish_at:[[:space:]]*//p' | head -1)
  ZIVIL="${ROH%%+*}"      # Offset abschneiden -- publish_at ist immer Berliner Ortszeit
  ZIVIL="${ZIVIL%%Z*}"

  if ! ZIEL_SEK=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$ZIVIL" +%s 2>/dev/null); then
    echo "FEHLER: $PID hat kein lesbares publish_at ('$ROH')." >> "$LOG"
    PLANTABELLE="${PLANTABELLE}${PID} | UNLESBAR | publish_at nicht interpretierbar
"
    continue
  fi

  if awk '/^---$/{n++; next} n>=2' "$f" | grep -qiE 'montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonnabend|sonntag'; then
    SCHRITT=7
  else
    SCHRITT=1
  fi

  ZIEL="$ZIVIL"
  TAGE=0
  while [ "$ZIEL_SEK" -lt $((JETZT_SEK + VORLAUF_SEK)) ] && [ "$TAGE" -lt 400 ]; do
    ZIEL=$(date -j -v+${SCHRITT}d -f "%Y-%m-%dT%H:%M:%S" "$ZIEL" "+%Y-%m-%dT%H:%M:%S")
    ZIEL_SEK=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$ZIEL" +%s)
    TAGE=$((TAGE + SCHRITT))
  done

  # Reissleine: der Zaehler oben deckt gut ein Jahr ab. Wer hier landet, hat
  # einen Post aus einer anderen Zeitrechnung -- lieber sichtbar liegen lassen
  # als mit einem Termin in der Vergangenheit an Metricool schicken.
  if [ "$ZIEL_SEK" -lt $((JETZT_SEK + VORLAUF_SEK)) ]; then
    echo "FEHLER: $PID liegt zu weit in der Vergangenheit ('$ROH'), Termin nicht bestimmbar." >> "$LOG"
    PLANTABELLE="${PLANTABELLE}${PID} | UNLESBAR | publish_at liegt zu weit in der Vergangenheit
"
    continue
  fi

  OFFSET=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$ZIEL" +%z)   # +0200 / +0100
  OFFSET="${OFFSET:0:3}:${OFFSET:3:2}"                    # -> +02:00
  if [ "$TAGE" -eq 0 ]; then
    HINWEIS="unveraendert"
  else
    HINWEIS="verschoben um $TAGE Tag(e) (Original $ZIVIL), Uhrzeit unveraendert"
  fi
  PLANTABELLE="${PLANTABELLE}${PID} | ${ZIEL}${OFFSET} | ${HINWEIS}
"
  echo "Termin $PID -> ${ZIEL}${OFFSET} ($HINWEIS)" >> "$LOG"
done

echo "Gefundene Posts mit status: ready = $READY_COUNT" >> "$LOG"
if [ "$READY_COUNT" -eq 0 ]; then
  echo "Nichts zu tun." >> "$LOG"
  return 0
fi

if [ -z "${AURALEX_BLOG_ID:-}" ]; then
  echo "FEHLER: AURALEX_BLOG_ID ist nicht gesetzt, aber $READY_COUNT Post(s) warten. Siehe Setup-Checkliste (blogId per mcp__metricool__getBrands ermitteln, in der launchd-plist eintragen)." >> "$LOG"
  return 1   # Konfigurationsfehler, WIEDERHOLBAR bleibt 0 - ein Retry aendert nichts
fi

PROMPTFILE="$REPO/out/tick-prompt.txt"
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

   0b) Sendetermin (nach Schritt 0, VOR Schritt a):
      Der Termin ist bereits ausgerechnet. Rechne selbst NICHTS aus, leite
      nichts her und pruefe keine Zeitpunkte gegen die Uhr -- nimm ausschliess-
      lich den Wert aus dieser Tabelle (Format: id | Sendetermin | Hinweis):

${PLANTABELLE}
      Steht bei einem Post "UNLESBAR", plane ihn nicht ein: setze status auf
      "error", committe/pushe (siehe c) und mach mit dem naechsten weiter.

      Der Sendetermin ersetzt publish_at aus der Datei vollstaendig, auch wenn
      dir der Wert seltsam vorkommt. Steht im Hinweis "verschoben", schreibst
      du ihn in Schritt (c) in die publish_at-Zeile und nennst die Verschiebung
      im "detail"-Feld des Abschlussberichts. Steht dort "unveraendert",
      bleibt die Datei bei publish_at unangetastet.

      Hintergrund, nur zur Einordnung: Davids Generator setzt publish_at auf
      die Erzeugungszeit, der Lauf ist aber einmal taeglich. Was nach dem Lauf
      entsteht, liegt am naechsten Morgen zwangslaeufig in der Vergangenheit;
      Metricool lehnt das hart ab. Die Uhrzeit bleibt dabei immer Davids
      Uhrzeit, verschoben wird nur der Tag.

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
      - date: der Sendetermin aus Schritt 0b ohne Zeitzonen-Suffix,
        Format YYYY-MM-DDTHH:MM:SS
      - info.text: der Caption-Body aus der Markdown-Datei (unveraendert!).
      - info.media: fuer jeden Dateinamen in "assets" die URL
        https://raw.githubusercontent.com/xbenlange99-dot/auralex-content/main/assets/<id>/<dateiname>
        in der Reihenfolge der Liste (Reihenfolge = Karussell-Reihenfolge).
      - info.providers: ein Eintrag pro Netzwerk in "channels", also
        {"network":"facebook"} und/oder {"network":"instagram"}
      - info.publicationDate: {"dateTime": derselbe Sendetermin ohne Offset, "timezone":"Europe/Berlin"}
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
      und, falls die Tabelle in Schritt 0b "verschoben" sagt, die
      publish_at-Zeile auf den Sendetermin aus der Tabelle (mit Offset, exakt
      wie dort geschrieben). Aendere sonst NICHTS an der Datei, insbesondere
      nicht den Caption-Text. Dann:
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
LAUFAUSGABE=$(mktemp)
"$CLAUDE" -p "$(cat "$PROMPTFILE")" \
  --dangerously-skip-permissions \
  --allowedTools "Read" "Edit" "Bash(git:*)" \
                 "mcp__metricool__getScheduledPosts" "mcp__metricool__createScheduledPost" \
  > "$LAUFAUSGABE" 2>&1
RC=$?
cat "$LAUFAUSGABE" >> "$LOG"

# --- Ergebnis pruefen, nicht nur den Rueckgabewert ---
# Claude beendet sich mit 0, auch wenn es den Auftrag gar nicht ausgefuehrt hat
# (nicht autorisiertes MCP, gesperrter Zugang). Am 29. und 30.07.2026 blieben so
# 22 bzw. 3 Posts liegen, waehrend die Statusdatei "OK" meldete. Ein Lauf gilt
# deshalb nur als erfolgreich, wenn der Abschlussbericht aus Schritt 4 da ist
# und ok:true sagt.
if [ "$RC" -eq 0 ]; then
  if ! grep -q '"ok"' "$LAUFAUSGABE"; then
    echo "FEHLER: Lauf endete ohne Abschlussbericht - $READY_COUNT Post(s) blieben unbearbeitet. Grund steht in der Ausgabe darueber (haeufig: Metricool-MCP nicht autorisiert oder Claude-Zugang gesperrt)." >> "$LOG"
    RC=1
  elif grep -qE '"ok"[[:space:]]*:[[:space:]]*false' "$LAUFAUSGABE"; then
    echo "FEHLER: Abschlussbericht meldet ok:false - mindestens ein Post wurde nicht eingeplant." >> "$LOG"
    RC=1
  elif grep -qE '"status"[[:space:]]*:[[:space:]]*"(error|skipped)"' "$LAUFAUSGABE"; then
    echo "FEHLER: Abschlussbericht enthaelt Posts mit status error/skipped - diese wurden NICHT eingeplant." >> "$LOG"
    RC=1
  else
    # Auch ein halb abgearbeiteter Lauf ist ein Fehlschlag: der Bericht muss
    # ueber JEDEN ready-Post Auskunft geben, sonst ist stillschweigend etwas
    # liegen geblieben.
    BERICHTET=$(grep -o '"status"[[:space:]]*:' "$LAUFAUSGABE" | wc -l | tr -d ' ')
    if [ "$BERICHTET" -ne "$READY_COUNT" ]; then
      echo "FEHLER: Bericht deckt $BERICHTET von $READY_COUNT ready-Post(s) ab - der Rest blieb unbearbeitet." >> "$LOG"
      RC=1
    fi
  fi
fi
# --- Wiederholbar oder endgueltig? ---
# Am 08.08.2026 starb der Lauf an "API Error: Connection closed mid-response",
# bevor ein einziger Metricool-Call rausging -- ein Transportfehler kostete
# damit den kompletten Tag. Solche Abbrueche werden wiederholt.
# NICHT wiederholt wird ein nicht autorisiertes MCP (Falle 1 in BETRIEB.md):
# das faellt bei jedem Versuch identisch aus und laesst sich nur interaktiv von
# Ben im Browser loesen -- drei Versuche verzoegern dort nur den Alarm.
if [ "$RC" -ne 0 ]; then
  if grep -qiE 'needs authentication|not authorized|nicht autorisiert|unauthorized' "$LAUFAUSGABE"; then
    echo "Nicht wiederholbar: Metricool-MCP ist nicht autorisiert. Das kann nur Ben interaktiv beheben (BETRIEB.md, Falle 1)." >> "$LOG"
  elif grep -qiE 'API Error|Connection closed|Connection error|fetch failed|socket hang up|ECONNRESET|ETIMEDOUT|Overloaded|\b(502|503|529)\b' "$LAUFAUSGABE"; then
    WIEDERHOLBAR=1
  fi
fi
rm -f "$LAUFAUSGABE"
return $RC
}
# --- Ende versuch() ---------------------------------------------------------

# --- Bis zu drei Versuche ---------------------------------------------------
# Ein Wiederholen ist gefahrlos: Schritt (a) im Prompt prueft vor jedem Planen
# per getScheduledPosts ein +-3-h-Fenster gegen Metricool und ueberspringt, was
# ein abgebrochener Vorversuch schon eingeplant hat.
MAX_VERSUCHE=3
RC=1
for VERSUCH in $(seq 1 "$MAX_VERSUCHE"); do
  echo "--- Versuch $VERSUCH/$MAX_VERSUCHE $(date) ---" >> "$LOG"
  versuch
  RC=$?
  [ "$RC" -eq 0 ] && break
  [ "$WIEDERHOLBAR" -eq 1 ] || break
  [ "$VERSUCH" -lt "$MAX_VERSUCHE" ] || { echo "Auch der $MAX_VERSUCHE. Versuch scheiterte - gebe auf." >> "$LOG"; break; }
  echo "Transienter Fehler - naechster Versuch in 120 s." >> "$LOG"
  sleep 120
done

echo "--- fertig (rc=$RC, Versuche: $VERSUCH) $(date) ---" >> "$LOG"
exit $RC   # Statusdatei und Benachrichtigung erledigt der EXIT-Trap
