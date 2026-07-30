# auralex-content — Ablage und Auslieferung der Auralex-Posts

Dieser Ordner ist **kein Teammitglied und keine Rolle**. Er ist die Warteschlange:
hier liegen die fertigen Posts, und ein Skript trägt sie zum vereinbarten Zeitpunkt
nach Metricool. Es gibt hier nichts zu entscheiden — entschieden wird woanders.

**Wer entscheidet, was gepostet wird:** Promoticus, `~/Projekte/Auralex/Marketing/`.
Dort liegen Strategie (`STRATEGIE.md`), Botschaften (`BOTSCHAFTEN.md`) und die belegten
Erfahrungen (`ERFAHRUNGEN.md`). Wer hier Text schreibt, ohne die gelesen zu haben,
schreibt am Plan vorbei.

*(Bis 30.07.2026 hieß diese Aufgabe „Publikus" und war als eigene Rolle geführt. Sie
ist aufgelöst: Inhalte macht Promoticus, das Ausliefern macht das Skript. Siehe
`~/Assistent/SYSTEMKARTE.md`, Änderungslog.)*

## Der Weg eines Posts

```
Promoticus schreibt posts/<id>.md + assets/<id>/     status: draft
        ↓  (Post ist fertig)                         status: ready
        ↓  git commit + push  ← nötig, s. u.
07:00 launchd → scripts/tick.sh → Metricool-MCP      status: scheduled
        ↓
Metricool veröffentlicht zur publish_at-Zeit
```

Eilfall zwischendurch: `scripts/posten.command` doppelklicken. Ein Lauf, dann Ende.

**Warum GitHub?** Nur weil Metricool die Bilder und Videos von einer öffentlichen URL
laden muss. Es ist kein Entwicklungs-Remote und kein Backup — es ist der Bilder-Hoster.
Daraus folgt die wichtigste Regel dieses Ordners:

> **Das Repo ist öffentlich.** Hier liegen ausschließlich Captions und Medien, die
> ohnehin in Kürze öffentlich sind. Keine Strategiepapiere, keine Briefings, keine
> Kundendaten, keine Zahlen, keine unveröffentlichten Ankündigungen. Interne Doku
> gehört nach `~/Projekte/Auralex/Marketing/`.

## Frontmatter — der Vertrag

```yaml
---
id: 2026-07-30-1240-entsorgung-nicht-berechnet   # = Dateiname ohne .md = Asset-Ordner
status: draft                                     # draft | ready | scheduled | error
format: video                                     # image | carousel | video
channels: [facebook, instagram]                   # nur diese beiden, s. u.
publish_at: 2026-07-31T07:30:00+02:00             # +02:00 Sommer, +01:00 Winter
anlass: A0                                        # Kaufanlass A0–A6 (Promoticus)
stufe: 3                                          # Awareness-Stufe 1–5 (Promoticus)
assets:
  - reel.mp4
cover: cover.jpg                                  # optional, nur bei format: video
---
```

Alles unter der zweiten `---`-Linie ist die Caption, 1:1 wie sie draußen steht.

- **`anlass` und `stufe` sind Pflicht** (seit 30.07.2026). Ohne sie kann im Quartal
  niemand auswerten, welche Inhalte gewirkt haben — dann bleibt `ERFAHRUNGEN.md` für
  immer leer. Die Bedeutungen stehen dort.
- **Nur `facebook` und `instagram`.** Es gibt genau eine Metricool-Brand (Auralex).
  `tiktok` oder `linkedin` in `channels` ist ein Konfigurationsfehler und setzt den
  Post auf `error`. Davids Personal Brand wurde am 30.07.2026 auf Bens Entscheidung
  ersatzlos ausgebaut — nicht ohne seine ausdrückliche Ansage wieder einführen.
- **`publish_at` nie in der Vergangenheit.** Metricool lehnt das hart ab
  („Publication date cannot be in the past"), der Post landet in `status: error`.
- **`status: scheduled` setzt das Skript**, nie ein Mensch. Und was `scheduled` ist,
  wird nicht mehr angefasst — die Datei steuert dann nichts mehr, der Post liegt
  bereits in Metricool.

## Beim Arbeiten in diesem Ordner

1. **Erst `git pull`**, sonst Konflikt beim Pushen.
2. Änderungen **einzeln committen und pushen**. Das Skript tut das auch so — ein Crash
   mitten im Lauf darf keine Doppel-Postings erzeugen.
3. `status: ready` ist der scharfe Schalter. Solange `draft` steht, passiert nichts.
4. Der 07:00-Lauf prüft **einmal täglich**. Wer um 09:00 auf `ready` stellt, ist erst
   am nächsten Morgen dran — oder startet `posten.command` selbst.

Wenn etwas nicht durchläuft: `BETRIEB.md` — dort stehen die bekannten Fallen samt
Ursache, und `out/tick.log` zeigt, was der letzte Lauf getan hat.

Für David gibt es eine eigene Anleitung ohne Technik: `ANLEITUNG.md`.
