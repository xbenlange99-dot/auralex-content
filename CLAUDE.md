# Auralex Content – Laufzeitregeln

Dieses öffentliche Repo ist ausschließlich Warteschlange und Medienhoster für den Auralex-Publisher. Die vollständige technische Beschreibung steht in `DOKUMENTATION.md`.

## Was hier liegen darf

- fertige Captions unter `posts/`
- veröffentlichbare Medien unter `assets/<post-id>/`
- Publisher-Konfiguration und Skripte

Keine Kundendaten, internen Zahlen, Strategiepapiere, Zugangsdaten oder unveröffentlichten Ankündigungen ablegen. Metricool lädt die Medien über öffentliche Raw-GitHub-URLs.

## Post-Vertrag

Jede Datei `posts/<id>.md` braucht einen gleichnamigen Asset-Ordner und dieses Frontmatter:

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

Gültige Statuswerte: `draft`, `ready`, `scheduled`, `error`. Gültige Formate: `image`, `carousel`, `video`. Gültige Kanäle: ausschließlich `facebook` und `instagram`. Alles nach dem zweiten `---` ist die Caption und wird unverändert ausgeliefert.

Weitere Frontmatter-Felder werden vom Publisher nicht benötigt. Ein `cover`-Feld und separate Vorschaubilder gehören nicht in den Post-Vertrag.

## Betriebsregeln

- Der automatische Lauf startet täglich um 07:00 Uhr über `scripts/tick.sh`; `scripts/posten.command` startet denselben Lauf manuell.
- Nur `status: ready` wird verarbeitet. `scheduled` niemals zurücksetzen oder nachträglich verändern; die maßgebliche Fassung liegt dann bereits in Metricool.
- Jeder Haupt-Post wird zusätzlich als Story auf denselben Kanälen angelegt. Ein Story-Fehler ist Best Effort und ändert den erfolgreichen Haupt-Post nicht auf `error`.
- Vor Änderungen immer `git pull --ff-only`. Posts werden einzeln committet und gepusht; nicht mehrere Statuswechsel bündeln.
- Für Git ausschließlich `git -C /Users/bl/Arbeit/Auralex/content ...` verwenden.
- `.mcp.json`, `.gitignore`, `scripts/`, `posts/`, `assets/` und `out/` sind Bestandteile des laufenden Publishers. Nicht löschen oder verschieben.
- Der letzte Zustand steht in `out/LETZTER-LAUF.txt`, Details in `out/tick.log`.
- Veröffentlichte Posts und Medien frühestens 30 Tage nach `publish_at` und nur nach bestätigter Veröffentlichung gemeinsam entfernen. Die Bereinigung erfolgt derzeit manuell.

Weitere Einzelheiten zu Terminberechnung, Metricool-Payload, Duplikatschutz, Git-Sicherung und Wiederholungen stehen in `DOKUMENTATION.md`.

Bei „Metricool-MCP nicht autorisiert“ muss Ben im Verzeichnis `/Users/bl/Arbeit/Auralex/content` eine interaktive Claude-Sitzung öffnen und den Browser-Login über `/mcp` erneuern. Headless-Läufe können das nicht selbst beheben.
