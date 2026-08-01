# auralex-content

Warteschlange für Auralex-Posts. Ein Skript trägt sie zum eingetragenen Zeitpunkt nach
Metricool. Hier wird nichts entschieden, nur abgelegt und ausgeliefert.

> **Das GitHub-Repo ist öffentlich.** Es dient nur als Bilder-Hoster, weil Metricool die
> Medien von einer öffentlichen URL laden muss. Hier liegen ausschließlich Captions und
> Medien, die ohnehin in Kürze öffentlich sind — keine Strategiepapiere, keine Briefings,
> keine Kundendaten, keine unveröffentlichten Ankündigungen.

## Ablauf

```
Davids Generator erzeugt posts/<id>.md + assets/<id>/ und pusht hierher   status: ready
07:00 launchd → scripts/tick.sh → Metricool                              status: scheduled
Metricool veröffentlicht zur publish_at-Zeit
```

Eilfall: `scripts/posten.command` doppelklicken — ein Lauf, dann Ende.

## Frontmatter

```yaml
id: 2026-07-30-1240-entsorgung-nicht-berechnet   # = Dateiname ohne .md = Asset-Ordner
status: draft                                     # draft | ready | scheduled | error
format: video                                     # image | carousel | video
channels: [facebook, instagram]
publish_at: 2026-07-31T07:30:00+02:00             # +02:00 Sommer, +01:00 Winter
anlass: A0                                        # Kaufanlass A0–A6
stufe: 3                                          # Awareness-Stufe 1–5
assets: [reel.mp4]
cover: cover.jpg                                  # nur bei format: video
```

Alles unter der zweiten `---`-Linie ist die Caption, 1:1 wie sie draußen steht.

## Was man beim Lesen nicht sieht

- Die Posts kommen aus einem Generator, der **bei David läuft** (git-Identität
  `auralex-ai <info@auralex-ai.de>`). Er pusht hierher.
- **Nur `facebook` und `instagram`** sind angebunden — eine einzige Metricool-Brand.
  `tiktok` oder `linkedin` in `channels` setzt den Post auf `error`.
- **`publish_at` nie in der Vergangenheit.** Metricool lehnt hart ab, der Post landet in
  `status: error`.
- **`status: scheduled` setzt das Skript, nie ein Mensch.** Was `scheduled` ist, wird nicht
  mehr angefasst — der Post liegt bereits in Metricool.
- `anlass` und `stufe` sind Pflicht, sonst lässt sich später nicht auswerten, was gewirkt hat.
- **Erst `git pull`**, dann arbeiten. Änderungen einzeln committen und pushen — ein Crash
  mitten im Lauf darf keine Doppel-Postings erzeugen.
- Der 07:00-Lauf prüft **einmal täglich**. Wer um 09:00 auf `ready` stellt, ist am nächsten
  Morgen dran.

Bekannte Fallen: `BETRIEB.md`. Was der letzte Lauf getan hat: `out/tick.log`.
Anleitung für David ohne Technik: `ANLEITUNG.md`.
