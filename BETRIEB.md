# Betrieb — Publisher: wie er läuft, was schiefgeht, was dann zu tun ist

Stand 30.07.2026. Diese Datei war bis dahin `AUFTRAG.md` (Auftrag „Posting-Rhythmus auf
täglich 07:00 umstellen" — **erledigt**). Sie ist jetzt das Betriebsprotokoll:
Mechanik, bekannte Fallen, Historie. Die Bedienung steht in `CLAUDE.md`/`ANLEITUNG.md`.

## Mechanik

| Teil | Wo | Was er tut |
|---|---|---|
| launchd-Job `com.auralex.metricool-publisher` | `~/Library/LaunchAgents/` | startet `tick.sh` täglich 07:00 (`StartCalendarInterval`) |
| `scripts/tick.sh` | hier | `git pull` → startet `claude` headless mit `cwd=$HOME` → Metricool-MCP → je Post `scheduled` + einzelner Commit + Push |
| `scripts/posten.command` | hier | derselbe Lauf, manuell per Doppelklick. Für Eilfälle |
| Lockfile `.tick.lock/` | hier | verhindert überlappende Läufe, Crash-Schutz nach 30 Min |
| `out/tick.log` | hier (gitignored) | was der letzte Lauf getan hat — **erste Anlaufstelle bei Problemen** |

Zwei Metricool-Brands in einer Pipeline: **Auralex** (`AURALEX_BLOG_ID=6521208`,
facebook/instagram) und **David Schnell** (`DAVID_BLOG_ID`, tiktok/linkedin).
`DAVID_BLOG_ID` ist bis heute nicht gesetzt — Davids `ready`-Posts werden pro Lauf
stillschweigend übersprungen, ohne Fehler. Das ist Absicht, aber es heißt auch:
**Davids Posts gehen aktuell nicht raus, egal was im Frontmatter steht.**

`cwd=$HOME` ist kein Versehen: das Metricool-MCP ist im HOME-Scope konfiguriert und
wird sonst nicht geladen.

## Bekannte Fallen

**1. „Metricool-MCP nicht autorisiert" → gar nichts wird eingeplant**
Das Login ist ein OAuth-Browser-Flow und lässt sich in keiner headless-Session
nachholen. Symptom: jeder Lauf bricht mit derselben Meldung ab, tagelang still.
Fix: Terminal.app → `cd ~/Code/auralex-content` → `claude` → `/mcp` → Login im Browser
bestätigen. **Das kann nur Ben**, keine Session von sich aus.
Am 28.–30.07. hat das 2 Tage lang unbemerkt jeden Lauf gekillt, bis Ben zufällig
nachfragte. Login am 30.07. erledigt, seither läuft es.
Prüfen ob autorisiert: `claude mcp list` — dort darf bei `metricool` kein
„Needs authentication" stehen.

**2. `publish_at` in der Vergangenheit → `status: error`**
Metricool lehnt hart ab („Publication date cannot be in the past"). Tritt vor allem
auf, wenn Posts wegen Falle 1 liegengeblieben sind und ihr Zeitpunkt inzwischen
vorbei ist. **Nicht automatisch verschieben** — mit Ben klären, weil die Tageszeit oft
zum Inhalt gehört (ein Feierabend-Post gehört nicht auf 09:00).

**3. `ready` nach 07:00 gesetzt → liegt einen Tag**
Kein Fehler, sondern der Rhythmus. Wer nicht warten will: `posten.command`.

## Offen

- **`DAVID_BLOG_ID` fehlt.** Solange die Metricool-Brand für David nicht existiert,
  bleiben seine 6 LinkedIn-Posts liegen. Danach in der launchd-plist ergänzen.
- **Kein Alarm bei Fehlschlag.** Der Lauf scheitert still ins Log. Vorschlag, falls es
  wieder abreißt: in `tick.sh` bei „nicht autorisiert" eine sichtbare Meldung
  (`osascript -e 'display notification …'`) statt stillem Log-Eintrag.
- **Refresh-Token-Lebensdauer unbekannt.** Claude Code legt MCP-OAuth-Credentials
  nutzerweit auf der Platte ab, nicht sessiongebunden — eine einmalige Anmeldung
  sollte also auch für die headless-Läufe reichen. Ob Metricools Token dauerhaft hält,
  zeigt sich erst über mehrere Tage. Beobachten via `out/tick.log`.
- **Ein Post steht auf `status: error`:** `2026-07-15-0730-am-monatsende-nichts-suchen`
  (`publish_at` 15.07., längst vorbei — Falle 2). Braucht einen neuen Zeitpunkt oder
  wird verworfen. Entscheidung liegt bei Promoticus/Ben.
- **`.git` ist 203 MB** (Videos in der Historie, wachsend). Noch unkritisch, aber
  jeder `git pull` im launchd-Lauf zieht daran. Irgendwann Thema.

## Historie

**24.07.2026** — Umstellung vom 15-Minuten-Dauerjob auf täglich 07:00 (Bens
ausdrücklicher Beschluss für genau diesen Job). Das alte Plist liegt archiviert unter
`~/Claude-Archiv/2026-07-22/launchagents-gestoppt/com.auralex.metricool-publisher.plist`
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

**30.07.2026, 13:00** — Rolle „Publikus" aufgelöst. Inhaltliche Hoheit liegt bei
Promoticus (`~/Projekte/Auralex/Marketing/`), das Ausliefern ist reine Mechanik ohne
eigenen Namen. Gleichzeitig aufgeräumt: verwaister git-Worktree entfernt, interne
Strategiedokumente aus dem öffentlichen Repo geholt, Doku getrennt in `CLAUDE.md`
(Session), `ANLEITUNG.md` (David) und diese Datei (Betrieb).
