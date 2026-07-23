#!/usr/bin/env bash
# Auralex Content Publisher – Tick-Skript, laeuft alle 15 Min via launchd.
# Liest posts/*.md mit status: ready, prueft Duplikate in Metricool, plant sie
# via Metricool-MCP ein, setzt status: scheduled und pusht JEDEN Post einzeln
# zurueck (verhindert Doppel-Postings bei einem Crash mitten im Lauf).
# Postet je nach "channels" auf Facebook und/oder Instagram, jeweils als
# Feed-Post/Reel PLUS zusaetzlich als Story (seit 2026-07-15, best-effort,
# s. Schritt b2 im Prompt unten).
#
# Zwei getrennte Metricool-Brands in einer Pipeline (seit 2026-07-15):
#  - Auralex (Firma): channels facebook/instagram, Blog-Id $AURALEX_BLOG_ID.
#  - David Schnell (Personal Brand): channels tiktok/linkedin, Blog-Id
#    $DAVID_BLOG_ID. Bis die Metricool-Brand fuer David existiert und die
#    Variable in der launchd-plist gesetzt ist, werden seine ready-Posts pro
#    Tick uebersprungen (kein Fehler, siehe Schritt 0 im Prompt) statt das
#    Skript abzubrechen. Setup dann: DAVID_BLOG_ID in
#    ~/Library/LaunchAgents/com.auralex.metricool-publisher.plist ergaenzen.
#  - Ein einzelner Post darf channels nur aus EINER der beiden Gruppen
#    befuellen, nie gemischt (unterschiedliche Metricool-Brands/BlogIds).
#
# Reliability-Fixes (aus der Helal-Produktion uebernommen):
#  - launchd hat ein minimales PATH -> claude-Pfad und PATH explizit setzen.
#  - Das Metricool-MCP ist im $HOME-Scope konfiguriert -> claude MUSS mit
#    cwd=$HOME gestartet werden, sonst wird das MCP nicht geladen.
#  - Lockfile verhindert ueberlappende Laeufe, falls ein Tick laenger als
#    15 Min dauert.
#  - git pull passiert VOR dem Claude-Aufruf als expliziter, laut
#    fehlschlagender Schritt (kein stiller Fehlschlag).

set -uo pipefail

export HOME="/Users/bl"
export PATH="/Users/bl/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
CLAUDE="/Users/bl/.local/bin/claude"
REPO="/Users/bl/Code/auralex-content"
LOG="$REPO/out/tick.log"
LOCKDIR="$REPO/.tick.lock"

mkdir -p "$(dirname "$LOG")"
echo "=== $(date) ===" >> "$LOG"

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
trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT

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
cat > "$PROMPTFILE" <<PROMPT_EOF
Du verwaltest die automatische Auralex-Social-Media-Warteschlange im Repo
${REPO} ueber das Metricool-MCP. Es gibt ZWEI getrennte Metricool-Brands in
dieser Pipeline:
  - Auralex (Firma), Netzwerke facebook/instagram, blogId ${AURALEX_BLOG_ID}
  - David Schnell (Personal Brand), Netzwerke tiktok/linkedin, blogId
    "${DAVID_BLOG_ID:-}" (leerer String = die Metricool-Brand fuer David
    existiert noch nicht, siehe Schritt 0)

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

   0) BlogId und Kanal-Zuordnung bestimmen (VOR jedem Tool-Call fuer diesen
      Post):
      - channels enthaelt ausschliesslich facebook und/oder instagram
        -> blogId = ${AURALEX_BLOG_ID}. Weiter mit (a).
      - channels enthaelt ausschliesslich tiktok und/oder linkedin
        -> blogId = "${DAVID_BLOG_ID:-}".
        Ist dieser Wert ein leerer String: ueberspringe diesen Post
        VOLLSTAENDIG (kein Tool-Call, KEINE Status-Aenderung an der Datei,
        kein Commit). Schreib exakt eine Zeile ins Bash-Log
        ("SKIP <id>: DAVID_BLOG_ID noch nicht gesetzt, Metricool-Brand fuer
        David existiert noch nicht") und mach mit dem naechsten Post weiter.
        Ist der Wert nicht leer: weiter mit (a).
      - Jeder andere Fall (channels mischt Auralex- und David-Netzwerke im
        selben Post; ein Netzwerk-Wert ist unbekannt; format: text taucht
        zusammen mit einem anderen Kanal als ausschliesslich linkedin auf;
        tiktok taucht mit einem anderen format als video auf): das ist ein
        Konfigurationsfehler, kein Tool-Call. Setze status auf "error" mit
        einer kurzen Begruendung im Bash-Log, committe/pushe (siehe c), und
        mach mit dem naechsten Post weiter.

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
        Bei format: text ist das der komplette LinkedIn-Text.
      - info.media: fuer jeden Dateinamen in "assets" die URL
        https://raw.githubusercontent.com/xbenlange99-dot/auralex-content/main/assets/<id>/<dateiname>
        in der Reihenfolge der Liste (Reihenfolge = Karussell-Reihenfolge).
        Bei format: text gibt es keine assets, info.media bleibt [].
      - info.providers: ein Eintrag pro Netzwerk in "channels", also je nach
        Frontmatter eine Kombination aus {"network":"facebook"},
        {"network":"instagram"}, {"network":"tiktok"}, {"network":"linkedin"}
      - info.publicationDate: {"dateTime": publish_at ohne Offset, "timezone":"Europe/Berlin"}
      - info.autoPublish: true, info.draft: false, info.shortener: false
      - info.instagramData: {"type":"POST","tags":[]}  (nur wenn instagram in channels)
      - info.facebookData: {"type":"POST","title":""}
        (nur wenn facebook in channels; KEIN "boost"-Feld setzen -- die
        Metricool-API akzeptiert dort nur Werte >2.0 und lehnt boost:0 ab,
        also das Feld bei unbeworbenen Posts einfach weglassen)
      - info.tiktokData: {"disableComment":false,"disableDuet":false,
        "disableStitch":false,"privacyOption":"PUBLIC_TO_EVERYONE",
        "commercialContentThirdParty":false,"commercialContentOwnBrand":false,
        "autoAddMusic":false} (nur wenn tiktok in channels; David postet
        organisch, keine Commercial-Content-Kennzeichnung)
      - info.linkedinData: {"type":"post","publishImagesAsPDF":false,
        "previewIncluded":true} (nur wenn linkedin in channels)
      - SONDERFALL format: video (Reel/TikTok-Clip): "assets" enthaelt genau
        EINE mp4-Datei, info.media ist dann diese eine mp4-URL (gleiches
        raw.githubusercontent-Schema).
        - facebook in channels: info.facebookData: {"type":"REEL","title":""}
          statt POST.
        - instagram in channels: info.instagramData: {"type":"REEL","tags":[]}
          statt POST.
        - tiktok ist in dieser Pipeline immer Video, kein weiterer Typ noetig
          (info.tiktokData wie oben).
        Schlaegt der Aufruf fuer facebook/instagram mit einem Typ-Fehler fehl,
        versuche es EINMAL erneut mit {"type":"POST","title":""} bzw.
        {"type":"POST","tags":[]} (Video-Post statt Reel), bevor du den Post
        auf error setzt. Fuer tiktok gibt es diesen Retry nicht.
      - SONDERFALL format: text (nur channels: [linkedin], reiner Textpost
        ohne Medium): info.media bleibt [], info.linkedinData wie oben mit
        "type":"post". Diese Kombination wurde in Schritt 0 bereits als
        gueltig bestaetigt.
      Wenn der Aufruf fehlschlaegt: setze status auf "error" statt "scheduled",
      committe/pushe trotzdem (siehe c), und fahre mit dem NAECHSTEN Post fort.
      Erfinde KEINE erfolgreiche Planung, wenn der Tool-Call einen Fehler
      zurueckgab.

   b2) ZUSAETZLICH zu (b) -- Story-Version (seit 2026-07-15, David-Wunsch:
      jeder Auralex-Post soll auf Facebook UND Instagram als Feed-Post/Reel
      PLUS als Story laufen). GILT NUR fuer Posts, deren channels facebook
      und/oder instagram enthalten. Fuer tiktok/linkedin (Davids Kanaele)
      existiert kein Story-Schritt -- ueberspringe b2 fuer solche Posts
      komplett und mach direkt mit (c) weiter.

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
      auch nichts): bearbeite NUR die status-Zeile im Frontmatter dieser
      einen Datei (ready -> scheduled, oder ready -> error bei Fehlschlag).
      Aendere sonst NICHTS an der Datei. Dann:
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
exit $RC
