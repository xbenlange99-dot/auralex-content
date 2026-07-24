# Auralex Content – so postest du

Hey! Dieses Repo ist die Warteschlange für Auralex-Posts auf Facebook und
Instagram. Du legst hier deine Grafiken und Texte ab, markierst sie als
fertig – und ein automatischer Prozess plant sie dann direkt in Metricool
ein. Du brauchst dafür NIE einen Metricool-Login.

## So postest du etwas Neues

1. **Ordner für die Grafiken anlegen** unter `assets/<post-id>/`, z. B.
   `assets/2026-07-20-kundenfeedback/`. Lege dort deine Bilder ab
   (`slide-01.jpg`, `slide-02.jpg`, ... – bei einem Karussell zählt die
   alphabetische Reihenfolge der Dateinamen als Anzeigereihenfolge).

2. **Markdown-Datei anlegen** unter `posts/`, gleicher Name wie der
   Asset-Ordner plus `.md`, z. B. `posts/2026-07-20-kundenfeedback.md`.
   Kopiere am einfachsten `posts/2026-07-15-beispiel-post.md` als Vorlage.

3. **Frontmatter ausfüllen** (der Block zwischen den `---`-Linien oben):

   ```yaml
   ---
   id: 2026-07-20-kundenfeedback
   status: draft
   format: carousel          # image = ein Bild, carousel = mehrere Bilder
   channels: [facebook, instagram]
   publish_at: 2026-07-20T18:30:00+02:00
   assets:
     - slide-01.jpg
     - slide-02.jpg
   ---
   ```

   - `id`: identisch zum Dateinamen (ohne `.md`) und zum Asset-Ordnernamen.
   - `format`: `image` für ein einzelnes Bild, `carousel` für mehrere Bilder,
     `video` für ein Reel (genau EINE .mp4 in `assets`, 9:16, wird auf
     Facebook/Instagram als Reel geplant).
   - `cover` (optional, seit 2026-07-20, nur bei `format: video` relevant):
     Dateiname eines Bilds im selben Asset-Ordner (z. B. `cover.jpg`), das
     als Thumbnail/Cover für das Reel verwendet werden soll, statt Frame 0
     des Videos. Grund: unsere Reels starten oft mit einem kurzen
     Schwarzbild-Intro, das sonst als hässliches schwarzes Cover im
     Profil-Grid landet. Falls Metricool das Cover-Feld beim automatischen
     Einplanen (per API) noch nicht übernimmt, bitte kurz Bescheid geben,
     dann schauen wir uns an, wie wir es reinbekommen.
   - `channels`: **immer `[facebook, instagram]`**, außer es gibt einen
     konkreten Grund für nur einen Kanal (z. B. ein Format, das auf
     Instagram nicht funktioniert). Im Zweifel beide Kanäle eintragen.
   - `publish_at`: Datum + Uhrzeit im Format `JJJJ-MM-TTTHH:MM:SS+02:00`
     (Sommerzeit) bzw. `+01:00` (Winterzeit). Wenn unsicher: frag Claude in
     deiner eigenen Session, es rechnet dir das gerne um. Der automatische
     Durchlauf prüft nur einmal täglich um 07:00 Uhr, ob etwas mit
     `status: ready` wartet – setzt du das erst NACH 07:00 Uhr, greift es
     erst am nächsten Tag. Plane also entsprechend Vorlauf ein.
   - `assets`: die Dateinamen aus deinem Asset-Ordner, in Post-Reihenfolge.

4. **Text schreiben**: alles unterhalb der zweiten `---`-Linie ist die
   Caption, die 1:1 so gepostet wird. Schreib sie also genau so, wie sie
   später auf Facebook/Instagram stehen soll.

5. **Wenn der Post wirklich fertig zum Posten ist**, ändere ganz oben im
   Frontmatter `status: draft` zu `status: ready`. Das ist der entscheidende
   Schritt – ALLES mit `status: ready` wird beim nächsten täglichen Lauf um
   07:00 Uhr automatisch in Metricool eingeplant und dann zur
   `publish_at`-Zeit veröffentlicht.

   Solange `status: draft` steht, passiert gar nichts – du kannst also in
   Ruhe an einem Post arbeiten, bevor du ihn "scharf schaltest".

6. **Committen und pushen** über GitHub Desktop:
   - Änderungen erscheinen links in der Liste.
   - Kurze Commit-Message eingeben (z. B. "Post Kundenfeedback fertig").
   - "Commit to main" klicken, dann "Push origin".

Das war's. Du musst nirgendwo sonst etwas klicken oder freigeben.

## Status-Werte – was bedeuten sie?

- `draft` – noch in Arbeit, wird ignoriert.
- `ready` – fertig, wird beim nächsten automatischen Durchlauf eingeplant.
- `scheduled` – wurde erfolgreich in Metricool eingeplant. **Diesen Wert
  setzt das System selbst, du musst hier nichts tun.** Sobald du das siehst,
  weißt du: der Post läuft.
- `error` – etwas ist beim Einplanen schiefgelaufen (z. B. Metricool war
  kurzzeitig nicht erreichbar). Sag in dem Fall kurz Bescheid, dann schaut
  sich das jemand an.

## Ein paar Regeln

- **Bevor du anfängst zu arbeiten**: in GitHub Desktop einmal "Fetch origin"
  bzw. "Pull" klicken, damit du auf dem neuesten Stand bist. Sonst kann es
  beim Pushen zu einer Konfliktmeldung kommen.
- Ändere niemals den Status eines Posts, der schon `scheduled` ist – der
  läuft bereits, eine nachträgliche Änderung der Datei ändert NICHTS mehr
  an dem, was tatsächlich gepostet wird (das passiert schon drüben in
  Metricool). Willst du einen bereits eingeplanten Post noch anpassen oder
  stoppen, sag kurz Bescheid.
- Dieses Repo ist **öffentlich auf GitHub** (aus rein technischen Gründen –
  Metricool muss die Bilder von irgendwo laden können). Also: keine
  Kundendaten, keine internen Zahlen, keine unveröffentlichten
  Ankündigungen hier reinlegen – nur fertige Marketing-Captions und -Bilder,
  die ohnehin in Kürze öffentlich werden.
- Aktuell unterstützt: Bilder, Karussells (mehrere Bilder) und Videos
  (Reels) auf Facebook und Instagram. Jeder Post läuft zusätzlich
  automatisch auch als Story auf beiden Plattformen (seit 2026-07-15).

Bei Fragen: einfach fragen, kein Problem.
