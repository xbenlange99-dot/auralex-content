# Betrieb — Publisher: wie er läuft, was schiefgeht, was dann zu tun ist

Stand 02.08.2026. Betriebsprotokoll: Mechanik, bekannte Fallen, Historie.
Die Bedienung steht in `CLAUDE.md`/`ANLEITUNG.md`.

## Mechanik

| Teil | Wo | Was er tut |
|---|---|---|
| launchd-Job `com.auralex.metricool-publisher` | `~/Library/LaunchAgents/` | startet `tick.sh` täglich 07:00 (`StartCalendarInterval`) |
| `scripts/tick.sh` | hier | `git pull` → Sendetermine rechnen → startet `claude` headless mit `cwd=$REPO` → Metricool-MCP → je Post `scheduled` + einzelner Commit + Push |
| `scripts/posten.command` | hier | derselbe Lauf, manuell per Doppelklick. Für Eilfälle |
| Lockfile `.tick.lock/` | hier | verhindert überlappende Läufe, Crash-Schutz nach 30 Min |
| `out/tick.log` | hier (gitignored) | was der letzte Lauf getan hat — **erste Anlaufstelle bei Problemen** |
| `out/LETZTER-LAUF.txt` | hier (gitignored) | eine Zeile: OK oder FEHLGESCHLAGEN mit Grund. Bei Fehlschlag zusätzlich eine Systemmeldung mit Ton |

**Eine Metricool-Brand:** Auralex (`AURALEX_BLOG_ID=6521208`, facebook/instagram).
Bis 30.07.2026 gab es eine zweite für „David Schnell (Personal Brand)"
(tiktok/linkedin, `DAVID_BLOG_ID`) — ausgebaut, siehe Historie. Ein Post mit
`tiktok` oder `linkedin` in `channels` ist jetzt ein Konfigurationsfehler.

Der Lauf startet `claude` mit `cwd=$REPO`, weil das Metricool-MCP über die `.mcp.json`
im Repo kommt. Von einem anderen Verzeichnis aus wird es nicht geladen, und der Lauf
scheitert mit „nicht autorisiert" (Falle 1).

**Die Sendetermine rechnet `tick.sh` selbst aus**, bevor `claude` überhaupt startet, und
übergibt sie als fertige Tabelle. Das Modell bekommt den Auftrag, selbst nichts
auszurechnen. Grund: Datumsarithmetik über Monats- und Zeitumstellungsgrenzen ist nichts,
was ein unbeaufsichtigter Job jede Nacht neu erwürfeln sollte — ein Rechenfehler landet
ungeprüft in Metricool. Wer daran etwas ändert: gerechnet wird in Zivilzeit
(`date -j -v+Nd -f …`, das `-v` **vor** dem `-f`, sonst schluckt `date` die Verschiebung
stillschweigend), nicht in Sekunden. Sonst verrutscht die Uhrzeit über die
Zeitumstellung um eine Stunde.

## Bekannte Fallen

**1. „Metricool-MCP nicht autorisiert" → gar nichts wird eingeplant**
Das Login ist ein OAuth-Browser-Flow und lässt sich in keiner headless-Session
nachholen. Symptom: jeder Lauf bricht mit derselben Meldung ab, tagelang still.
Fix: Terminal.app → `cd ~/Arbeit/Auralex/content` → `claude` → `/mcp` → Login im Browser
bestätigen. **Das kann nur Ben**, keine Session von sich aus.
Am 28.–30.07. hat das 2 Tage lang unbemerkt jeden Lauf gekillt, bis Ben zufällig
nachfragte. Login am 30.07. erledigt, seither läuft es.
Prüfen ob autorisiert: `claude mcp list` — dort darf bei `metricool` kein
„Needs authentication" stehen.

**2. `publish_at` in der Vergangenheit → wird verschoben, nicht verbrannt**
Metricool lehnt einen Zeitpunkt in der Vergangenheit hart ab („Publication date cannot
be in the past"). Weil Davids Generator `publish_at` auf die Erzeugungszeit setzt, der
Lauf aber nur einmal täglich prüft, wäre das der Normalfall statt der Ausnahme. Deshalb
verschiebt `tick.sh` auf den nächsten Tag, an dem der Zeitpunkt mindestens eine Stunde
in der Zukunft liegt. **Die Uhrzeit bleibt dabei immer unangetastet** — die Tageszeit
gehört zum Inhalt, ein Feierabend-Post gehört nicht auf 09:00. Nennt der Text einen
Wochentag („Samstagsfrage"), wird in 7-Tage-Schritten verschoben, damit die Aussage zum
Tag passt. Was verschoben wurde, steht in `out/tick.log` und im `detail`-Feld des
Abschlussberichts.

**3. `ready` nach 07:00 gesetzt → geht am Folgetag raus**
Kein Fehler, sondern der Rhythmus: ein Lauf pro Tag. Der Post behält seine Uhrzeit und
läuft am nächsten Tag zu genau dieser Uhrzeit. Wer nicht warten will: `posten.command`.

## Woran man einen Fehlschlag merkt

`tick.sh` wertet nicht den Rückgabewert von `claude` aus, sondern das Ergebnis. Das ist
der Unterschied, der zählt: `claude` beendet sich auch dann mit 0, wenn es die Arbeit
verweigert hat (nicht autorisiertes MCP, gesperrter Zugang). Am 29. und 30.07.2026 blieben
so 22 bzw. 3 Posts liegen, während die Statusdatei „OK" meldete.

Ein Lauf gilt nur als erfolgreich, wenn der Abschlussbericht da ist, `ok:true` sagt, kein
Post auf `error`/`skipped` steht **und** der Bericht genauso viele Posts abdeckt, wie
`ready` waren. Jeder andere Ausgang schreibt FEHLGESCHLAGEN in `out/LETZTER-LAUF.txt` und
löst eine Systemmeldung mit Ton aus.

## Offen

- **Refresh-Token-Lebensdauer unbekannt.** Claude Code legt MCP-OAuth-Credentials
  nutzerweit auf der Platte ab, nicht sessiongebunden — eine einmalige Anmeldung
  sollte also auch für die headless-Läufe reichen. Ob Metricools Token dauerhaft hält,
  zeigt sich erst über mehrere Tage. Beobachten via `out/tick.log`.
- **Ein Rückstau landet an einem Tag.** Steht der Job eine Woche still, werden alle
  liegengebliebenen Posts auf denselben nächsten Tag verschoben — jeder behält seine
  Uhrzeit, aber der Tag ist voll. Bisher nicht eingetreten, seit der Alarm greift auch
  unwahrscheinlich. Wenn es stört: Tagesobergrenze in `tick.sh` einziehen.
- **Drei Posts von Davids Generator hängen als `draft`** (`anfrage-schneller` vom 30.07.,
  `rechnung-liegt-seit-freitag` und `mappe-wird-jeden-abend-dicker` vom 31.07.). Sein
  Generator liefert sonst `ready`. Mit David klären: Absicht oder Aussetzer.
- **`.git` ist 203 MB** (Videos in der Historie, wachsend). Noch unkritisch, aber
  jeder `git pull` im launchd-Lauf zieht daran. Irgendwann Thema.

## Historie

**24.07.2026** — Umstellung vom 15-Minuten-Dauerjob auf täglich 07:00 (Bens
ausdrücklicher Beschluss für genau diesen Job). Das alte Plist liegt archiviert unter
`~/Archiv/Claude-Archiv/2026-07-22/launchagents-gestoppt/com.auralex.metricool-publisher.plist`
— nur nachschlagen, nicht zurückkopieren. Lockfile-Logik beibehalten.

**30.07.2026, 07:00** — Lauf scheitert, 3 `ready`-Posts bleiben liegen (Falle 1).
Ursache gefunden, Login von Ben nachgeholt (verifiziert per `getBrandSettings`: Brand
„Auralex", id 6521208, Zeitzone Europe/Berlin, facebook + instagram verbunden).

**30.07.2026, 12:45** — alle liegengebliebenen Posts nachgezogen, jeweils Reel + Story
auf beiden Kanälen, einzeln committet und gepusht: `notdienst-aufschlag` 13:30,
`konkurrent` 16:00, `notiz-feierabend` 18:30, `eigene-zeit` 20:00,
`lieferschein-verschwindet` 21:30, `entsorgung-nicht-berechnet`. Nebenfund dabei: die
Auto-Reel-Pipeline erzeugt Posts, deren `publish_at` schon bei Erzeugung in der
Vergangenheit liegt — läuft direkt in Falle 2.

**30.07.2026, 13:15** — **Davids Personal Brand ausgebaut** (Bens Entscheidung: „Wir
machen nichts mit Davids LinkedIn"). Entfernt: die 6 LinkedIn-Entwürfe (alle `draft`,
`publish_at`-Platzhalter vom 21.07., nie veröffentlicht), die komplette Zweit-Brand-Logik
in `tick.sh` (BlogId-Weiche, `tiktokData`, `linkedinData`, `format: text`, die
b2-Ausnahme) und `DAVID_BLOG_ID` aus `posten.command`. Die Handoff-Dokumente vom 15.07.
liegen in `~/Archiv/Claude-Archiv/2026-07-30-david-personal-brand/`. Es ist nie ein Post über
diese Kanäle rausgegangen — die Metricool-Brand für David existierte nie.

**30.07.2026, 13:00** — Die eigene Zuständigkeit fürs Ausliefern ist aufgelöst. Inhaltliche
Hoheit liegt beim Marketing (`~/Arbeit/Auralex/Marketing/`), das Ausliefern ist reine
Mechanik ohne eigene Zuständigkeit. Gleichzeitig aufgeräumt: verwaister git-Worktree entfernt, interne
Strategiedokumente aus dem öffentlichen Repo geholt, Doku getrennt in `CLAUDE.md`
(Session), `ANLEITUNG.md` (David) und diese Datei (Betrieb).
