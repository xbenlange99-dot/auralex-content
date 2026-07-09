#!/usr/bin/env bash
# Auralex Content Publisher – Tick-Skript, laeuft alle 15 Min via launchd.
# Liest posts/*.md mit status: ready, prueft Duplikate in Metricool, plant sie
# via Metricool-MCP ein, setzt status: scheduled und pusht JEDEN Post einzeln
# zurueck (verhindert Doppel-Postings bei einem Crash mitten im Lauf).
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
REPO="/Users/bl/Projects/auralex-content"
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
${REPO} ueber das Metricool-MCP.

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

   a) Sicherheitscheck vor dem Planen: rufe mcp__metricool__getScheduledPosts
      auf mit einem Zeitfenster von publish_at minus 3 Stunden bis publish_at
      plus 3 Stunden (blogId ${AURALEX_BLOG_ID}, timezone Europe/Berlin). Wenn
      dort bereits ein Post mit den ersten ~40 Zeichen eines nahezu
      identischen Texts existiert: gehe davon aus, dass ein vorheriger Tick
      das Scheduling bereits erfolgreich durchgefuehrt hat, aber der
      Status-Commit fehlgeschlagen ist. Plane NICHT erneut, sondern springe
      direkt zu Schritt (c) fuer diesen Post.

   b) Andernfalls rufe mcp__metricool__createScheduledPost auf mit:
      - blog_id: ${AURALEX_BLOG_ID}
      - date: publish_at ohne Zeitzonen-Suffix, Format YYYY-MM-DDTHH:MM:SS
      - info.text: der Caption-Body aus der Markdown-Datei (unveraendert!)
      - info.media: fuer jeden Dateinamen in "assets" die URL
        https://raw.githubusercontent.com/xbenlange99-dot/auralex-content/main/assets/<id>/<dateiname>
        in der Reihenfolge der Liste (Reihenfolge = Karussell-Reihenfolge)
      - info.providers: ein Eintrag {"network":"facebook"} und/oder
        {"network":"instagram"} je nach "channels" im Frontmatter
      - info.publicationDate: {"dateTime": publish_at ohne Offset, "timezone":"Europe/Berlin"}
      - info.autoPublish: true, info.draft: false, info.shortener: false
      - info.instagramData: {"type":"POST","tags":[]}  (nur wenn instagram in channels)
      - info.facebookData: {"type":"POST","title":""}
        (nur wenn facebook in channels; KEIN "boost"-Feld setzen -- die
        Metricool-API akzeptiert dort nur Werte >2.0 und lehnt boost:0 ab,
        also das Feld bei unbeworbenen Posts einfach weglassen)
      Wenn der Aufruf fehlschlaegt: setze status auf "error" statt "scheduled",
      committe/pushe trotzdem (siehe c), und fahre mit dem NAECHSTEN Post fort.
      Erfinde KEINE erfolgreiche Planung, wenn der Tool-Call einen Fehler
      zurueckgab.

   c) SOFORT nach (a) oder (b) fuer DIESEN Post: bearbeite NUR die
      status-Zeile im Frontmatter dieser einen Datei (ready -> scheduled,
      oder ready -> error bei Fehlschlag). Aendere sonst NICHTS an der Datei.
      Dann:
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
   {"ok": true|false, "processed": [{"id":"...", "status":"scheduled"|"error", "detail":"..."}]}
PROMPT_EOF

cd "$HOME" || exit 1
"$CLAUDE" -p "$(cat "$PROMPTFILE")" \
  --dangerously-skip-permissions \
  --allowedTools "Read" "Edit" "Bash(git:*)" \
                 "mcp__metricool__getScheduledPosts" "mcp__metricool__createScheduledPost" \
  >> "$LOG" 2>&1
RC=$?

echo "--- fertig (rc=$RC) $(date) ---" >> "$LOG"
exit $RC
