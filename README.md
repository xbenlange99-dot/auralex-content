# Auralex Content

Warteschlange für die Auralex-Posts auf Facebook und Instagram.
Post-Markdown in `posts/`, Medien in `assets/<post-id>/`,
`status: ready` setzen, committen, pushen — ein Skript auf Bens Mac plant den Rest
täglich um 07:00 in Metricool ein.

**Dieses Repo ist öffentlich**, weil Metricool die Medien von einer öffentlichen URL
laden muss. Nur fertige Captions und Medien, nichts Internes.

| Datei | Für wen |
|---|---|
| [ANLEITUNG.md](./ANLEITUNG.md) | David — wie man einen Post ablegt, ohne Technik |
| [CLAUDE.md](./CLAUDE.md) | Claude-Sessions — Frontmatter-Vertrag, Regeln, Zuständigkeit |
| [BETRIEB.md](./BETRIEB.md) | wenn etwas nicht durchläuft — Mechanik, bekannte Fallen |

Die Posts erzeugt ein Generator bei David und pusht sie hierher. Die Marketing-Vorgaben
(Strategie, Botschaften) liegen bei Promoticus in `~/Projekte/Auralex/Marketing/` —
beides ist heute nicht miteinander verbunden, siehe `CLAUDE.md`.
