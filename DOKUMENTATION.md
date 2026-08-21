# Auralex Metricool-Publisher

**Technischer Stand: 21. August 2026**

Dieses öffentliche GitHub-Repo ist Warteschlange und Medienhoster für die Veröffentlichung von Auralex-Beiträgen über Metricool.

## Bestandteile

- `.mcp.json` verbindet den ausführenden Claude-Prozess mit Metricool.
- `scripts/tick.sh` verarbeitet die Warteschlange.
- `scripts/posten.command` startet denselben Lauf manuell.
- `posts/` enthält Caption und Veröffentlichungsdaten je Beitrag.
- `assets/<post-id>/` enthält die zugehörigen Bilder oder Videos.
- `out/` enthält lokale Protokolle und Statusdateien und wird nicht in Git gespeichert.
- Der LaunchAgent `com.auralex.metricool-publisher` startet `tick.sh` täglich um 07:00 Uhr.

Metricool lädt Medien über öffentliche URLs nach dem Muster `https://raw.githubusercontent.com/xbenlange99-dot/auralex-content/main/assets/<id>/<dateiname>`. Deshalb müssen die für geplante Beiträge benötigten Dateien im Repo erreichbar bleiben. In das Repo gehören keine Kundendaten, Zugangsdaten oder sonstigen internen Unterlagen.

## Format eines Beitrags

Zu `posts/<id>.md` gehört der gleichnamige Ordner `assets/<id>/`. Der Publisher liest diese Felder aus dem Frontmatter:

```yaml
---
id: 2026-08-17-beispiel
status: draft
format: video
channels: [facebook, instagram]
publish_at: 2026-08-18T07:30:00+02:00
assets:
  - reel-01.mp4
---
```

- `id` entspricht Dateiname und Asset-Ordner.
- `status` ist `draft`, `ready`, `scheduled` oder `error`.
- `format` ist `image`, `carousel` oder `video`.
- `channels` enthält ausschließlich `facebook`, `instagram` oder beide.
- `publish_at` ist Berliner Ortszeit mit `+02:00` im Sommer und `+01:00` im Winter.
- `assets` enthält die Mediendateien in Veröffentlichungsreihenfolge.

Alles nach dem zweiten `---` ist die Caption und wird unverändert an Metricool übergeben. Weitere Frontmatter-Felder werden vom Publisher nicht benötigt. Separate Vorschaubilder und ein `cover`-Feld werden nicht erzeugt oder gespeichert, weil Metricool für diesen Ablauf ausschließlich die unter `assets` genannten Medien erhält.

## Statusablauf

- `draft`: wird ignoriert.
- `ready`: wird beim nächsten Lauf verarbeitet.
- `scheduled`: Hauptbeitrag wurde in Metricool nachgewiesen; diesen Status setzt nur der Publisher.
- `error`: der Hauptbeitrag konnte nicht eingeplant werden.

Ein bereits als `scheduled` markierter Beitrag darf nicht zurückgesetzt oder inhaltlich geändert werden. Die maßgebliche Fassung liegt dann in Metricool.

## Automatischer Lauf

Der LaunchAgent startet `scripts/tick.sh` täglich um 07:00 Uhr. Ein nach 07:00 Uhr eingehender `ready`-Beitrag wird normalerweise erst am folgenden Tag verarbeitet. `scripts/posten.command` ermöglicht einen manuellen Lauf.

Der Lauf verwendet eine einzige Metricool-Brand:

- Brand-ID: `6521208`
- Zeitzone: `Europe/Berlin`
- Netzwerke: Facebook und Instagram

Vor der Verarbeitung führt das Skript `git pull --ff-only` aus. Ein Lock verhindert parallele automatische und manuelle Läufe. Ein Lock unter 60 Minuten gilt als aktiv; ein älterer Lock wird als Überrest eines abgebrochenen Laufs entfernt.

## Terminberechnung

Der Publisher berechnet den Sendetermin in der Shell, bevor Claude gestartet wird. Claude bekommt eine fertige Termintabelle und darf die Zeit nicht selbst neu berechnen.

Liegt `publish_at` weniger als eine Stunde in der Zukunft, wird nur der Kalendertag verschoben. Die Uhrzeit bleibt erhalten. Enthält die Caption einen ausgeschriebenen Wochentag, erfolgt die Verschiebung in Sieben-Tage-Schritten; sonst tageweise. Die Berechnung arbeitet in Berliner Zivilzeit, damit die Uhrzeit beim Wechsel zwischen Sommer- und Winterzeit gleich bleibt.

Metricool lehnt Termine in der Vergangenheit ab. Die Terminverschiebung ist deshalb regulärer Bestandteil des Ablaufs. Für einen Rückstau existiert derzeit keine Tagesobergrenze.

## Einplanung in Metricool

Der Publisher verarbeitet `ready`-Beiträge einzeln und nach `publish_at` sortiert.

Vor dem Anlegen prüft er über Metricool ein Zeitfenster von drei Stunden vor bis drei Stunden nach dem Zieltermin. Existiert dort bereits ein Beitrag mit nahezu gleichem Text, wird kein Duplikat angelegt. Dieser Schutz deckt den Fall ab, dass Metricool den Beitrag erhalten hat, der anschließende Git-Commit aber ausgefallen ist.

Für Bilder und Karussells werden die Asset-URLs in der angegebenen Reihenfolge als Feed-Post übergeben. Bei `format: video` erwartet der Publisher genau eine MP4-Datei und verwendet auf Facebook und Instagram den Typ `REEL`. Lehnt Metricool den Reel-Typ ab, folgt genau ein Versuch als normaler Video-Post. Das Feld `boost` wird nicht gesendet.

Der Hauptbeitrag wird mit `autoPublish: true` und `draft: false` angelegt. Nach einem erfolgreichen Hauptbeitrag erzeugt der Publisher einen zweiten Metricool-Eintrag als Story mit demselben Medium und leerem Caption-Text. Auch vor der Story wird auf ein vorhandenes Duplikat geprüft. Ein Story-Fehler ist Best Effort: Er setzt einen erfolgreichen Hauptbeitrag nicht auf `error`.

## Git-Sicherung

Direkt nach jedem Beitrag ändert der Publisher nur dessen `status` und gegebenenfalls den verschobenen `publish_at`-Wert. Anschließend committet und pusht er genau diese eine Post-Datei. Erst danach wird der nächste Beitrag verarbeitet.

Bei einem Push-Konflikt führt der Publisher einmal `git pull --rebase` aus und versucht den Push erneut. Für manuelle Git-Arbeit gilt ausschließlich `git -C /Users/bl/Arbeit/Auralex/content ...`.

## Erfolgsprüfung und Wiederholungen

Der Rückgabecode des Claude-Prozesses genügt nicht als Erfolgsbeweis. Ein erfolgreicher Lauf braucht einen JSON-Abschlussbericht mit `ok: true`, muss jeden zuvor gefundenen `ready`-Beitrag abdecken und darf keinen Hauptbeitrag mit `error` oder `skipped` enthalten.

Bei Transportfehlern wie Verbindungsabbruch, Timeout, Überlastung oder HTTP 502/503/529 wird der vollständige Arbeitsteil höchstens dreimal mit jeweils 120 Sekunden Abstand wiederholt. Warteschlange und Termine werden vor jedem Versuch neu aufgebaut. Authentifizierungs- und Konfigurationsfehler werden nicht wiederholt.

## Diagnose

- `out/LETZTER-LAUF.txt` enthält den letzten Gesamtzustand.
- `out/tick.log` enthält den vollständigen Ablauf.
- Bei einem Fehlschlag zeigt macOS zusätzlich eine Mitteilung an.

### Abgelaufene Metricool-Anmeldung

Ein Metricool-Zugang gilt eine Stunde. Der Lauf tauscht ihn zu Beginn selbst gegen einen frischen; Metricool entwertet dabei den bisherigen Erneuerungsschlüssel und gibt einen neuen aus. Misslingt dieser Tausch, antwortet Metricool mit einem Serverfehler statt mit einer Ablehnung, das MCP bleibt unautorisiert und der Lauf plant nichts ein.

Der Lauf erkennt diesen Fall, wiederholt ihn nicht und meldet ihn als abgelaufene Anmeldung. Die Mitteilung und `out/LETZTER-LAUF.txt` nennen dann den Befehl:

    claude mcp login metricool

Nach der Bestätigung im Browser holt `scripts/posten.command` den Rückstau nach. Ein unbeaufsichtigter Lauf kann den Browser-Login nicht selbst durchführen.

Voraussetzung für diesen Befehl ist, dass `metricool` in `~/.claude.json` unter dem Projekteintrag `/Users/bl/Arbeit/Auralex/content` als freigegebener `.mcp.json`-Server steht. Die Freigabe in `.claude/settings.local.json` gilt nur für Sitzungen, nicht für die Kommandozeile.

## Aufbewahrung

- Ein Post und sein gleichnamiger Asset-Ordner bleiben mindestens 30 Tage über `publish_at` hinaus im Repository.
- Eine Löschung ist erst zulässig, wenn die Veröffentlichung in Metricool bestätigt ist. Post-Datei und Asset-Ordner werden dann immer gemeinsam entfernt.
- `draft`, `ready` und noch nicht veröffentlichte `scheduled`-Beiträge werden nicht durch eine Aufräumroutine gelöscht.
- Die Bereinigung erfolgt derzeit manuell. Das Entfernen alter Arbeitsdateien verkleinert nicht automatisch die bestehende Git-Historie; eine Historienbereinigung oder ein Wechsel des Medienhosters ist eine getrennte technische Entscheidung.

## Bekannte technische Grenzen

- Der Metricool-Zugang gilt eine Stunde und wird bei jedem Lauf erneuert. Scheitert die Erneuerung, hilft nur ein Browser-Login durch einen Menschen; der Publisher steht bis dahin still.
- Ein Rückstau besitzt keine Tagesobergrenze.
- Die Git-Historie wächst trotz der Aufbewahrungsregel weiter, solange GitHub selbst als Medienhoster dient.
