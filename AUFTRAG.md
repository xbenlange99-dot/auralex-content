# Posting-Rhythmus umstellen: täglich 07:00 statt alle 15 Min — Briefing für Publikus

**Rolle dieser Session: Du bist Publikus, zuständig für Auralex-Content und das Posten (Metricool).**

**So startest du:** Claude öffnen → Ordner `~/Code/auralex-content` wählen → erste Nachricht:
> Lies AUFTRAG.md und stell den Posting-Lauf auf täglich 7 Uhr um.

## Ausgangslage (Ben, 24.07.2026)
Aktuell läuft **nichts automatisch** — `tick.sh` wird nur manuell über `scripts/posten.command` angestoßen (Kommentar dort: „ersetzt den 15-Min-Dauerjob"). Der alte Dauerjob war ein launchd-Plist, der `tick.sh` alle 15 Minuten getriggert hat; er ist gestoppt und liegt archiviert unter `~/Claude-Archiv/2026-07-22/launchagents-gestoppt/com.auralex.metricool-publisher.plist` (nur nachschlagen, nicht zurückkopieren).

`CLAUDE.md` und der Kopf-Kommentar in `scripts/tick.sh` beschreiben aktuell noch das alte 15-Minuten-Verhalten — das ist inzwischen veraltete Doku.

Laut SYSTEMKARTE (Punkt 3, „Laufende Vorhaben") wartet der Publisher außerdem noch auf einen einmaligen Metricool-Browser-Login (`/mcp` in dieser Session) und einen beaufsichtigten Erstlauf — 74 Posts warten. Falls das noch nicht erledigt ist, das zuerst mit Ben klären, bevor Automatik wieder scharf gestellt wird.

## Auftrag
Automatisierten Lauf **wieder einrichten**, aber **nicht mehr alle 15 Minuten** — **genau einmal täglich um 07:00 Uhr**. Das ist Bens expliziter Beschluss für diesen Dauerjob (Leitplanke in `CLAUDE.md`: Automationen nur mit ausdrücklicher Freigabe — die liegt hiermit vor, für diesen einen Job).

1. **Mechanik wählen**: naheliegend ist ein launchd-Plist analog zum alten Muster, aber mit `StartCalendarInterval` (Hour 7, Minute 0) statt `StartInterval` 900s — Referenz: das archivierte Plist oben. Alternativ ein Scheduled-Task/Cron-Mechanismus dieser Session, falls robuster. Deine Entscheidung, du kennst die Details.
2. **Lockfile-Logik** (30-Min-Crash-Schutz in `tick.sh`) bleibt sinnvoll, auch im Tages-Rhythmus — nicht entfernen.
3. **`posten.command` bleibt zusätzlich bestehen** als manueller Sofort-Trigger für Eilfälle zwischen den Tages-Läufen.
4. **Doku nachziehen**: Kopf-Kommentar in `scripts/tick.sh` („läuft alle 15 Min via launchd") und den Passus in `CLAUDE.md` („automatisch (innerhalb von ca. 15 Minuten) eingeplant") auf „täglich um 7 Uhr" aktualisieren.
5. **Wenn es läuft**: Ben kurz Bescheid geben. Die SYSTEMKARTE (`~/Assistent/SYSTEMKARTE.md`, Punkt 3 „Laufende Vorhaben" + Änderungslog) muss dann noch nachgezogen werden — sag Ben, dass Schlaubi das übernimmt, sobald er es weiß.

## Status
- [x] Metricool-Login/Erstlauf-Status geprüft
- [x] Automatik auf 07:00 täglich umgestellt (launchd-Job `com.auralex.metricool-publisher` läuft, `StartCalendarInterval` 7:00)
- [ ] Doku (`tick.sh`-Kommentar, `CLAUDE.md`) aktualisiert
- [ ] Ben + Schlaubi (SYSTEMKARTE) informiert

## Nachtrag 30.07.2026 (Schlaubi, auf Bens Nachfrage „warum ist heute nix eingeplant")
Der 07:00-Job läuft (siehe `out/tick.log`), aber **Punkt 1 oben ist immer noch offen** — das ist die Ursache. Jeder Lauf seit mindestens 28.07. bricht mit derselben Meldung ab:

> „Der Metricool-MCP-Server ist in dieser Session nicht autorisiert – ich kann daher keine Metricool-Tools aufrufen (weder `getScheduledPosts` noch `createScheduledPost`). Das lässt sich in einer nicht-interaktiven Session nicht per OAuth nachholen."

Heute (30.07., 07:00) waren **3 `ready`-Posts** liegen geblieben, darunter der heutige `2026-07-30-0727-notdienst-aufschlag` — keiner wurde eingeplant, keine Datei geändert.

**Nächster Schritt:** einmalig interaktiv autorisieren — Session in diesem Ordner öffnen, `/mcp` ausführen, Metricool-Login im Browser bestätigen. Danach die 3 wartenden Posts nachziehen (`scripts/posten.command` oder auf den nächsten 07:00-Tick warten).

## Nachtrag 30.07.2026, 11:40 (Publikus, Versuch Login/Erstlauf)

**Login in dieser Session nicht möglich — anderer Grund als vermutet.** Nicht (nur)
"noch nicht gemacht", sondern: diese Chat-Session läuft in einer Umgebung, die
selbst als "non-interactive" markiert ist — OAuth-Browser-Flows lassen sich
hier grundsätzlich nicht abschließen, unabhängig vom `/mcp`-Befehl. Bestätigt
per `claude mcp list`: `metricool: ... - ! Needs authentication` (weiterhin
unautorisiert, kein einziger Tool-Call möglich — daher auch keine
`getScheduledPosts`-Verifikation machbar).

**Um das zu lösen, wird eine ECHTE interaktive Terminal-Session gebraucht:**
Terminal.app öffnen → `cd ~/Code/auralex-content` → `claude` starten → `/mcp`
→ Metricool-Login im sich öffnenden Browserfenster bestätigen. Das kann nur
Ben selbst machen (Browser-Login), nicht Publikus aus dieser Session heraus.

**Die 3 liegen gebliebenen Posts sind weiterhin unbearbeitet:**
`2026-07-29-1521-konkurrent`, `2026-07-29-1717-notiz-feierabend`,
`2026-07-30-0727-notdienst-aufschlag` — alle noch `status: ready`, keine
Dateiänderung. Zusätzliches Problem, das beim Nachziehen zuschlagen wird:
alle drei `publish_at`-Zeitpunkte liegen inzwischen in der Vergangenheit
(29.07. 15:46 / 17:17, 30.07. 07:27 — aktuelle Zeit 30.07. 11:40). Laut
Metricool-API-Verhalten vom 29.07. (siehe `out/tick.log`, Post
`urlaub-vertretung`) wird ein vergangenes `publish_at` mit "Publication date
cannot be in the past" abgelehnt → diese 3 Posts brauchen VOR dem nächsten
erfolgreichen Lauf neue `publish_at`-Werte, sonst laufen sie in `status:
error`. Mit Ben klären statt automatisch verschieben.

**Update 11:45:** Ben hat sich für "nächstmöglicher Slot" entschieden.
`publish_at` in den 3 Dateien korrigiert (Tageszeit-Charakter erhalten, wo er
zum Inhalt passt — Feierabend-Post bleibt abends, Notdienst-Post bleibt
früh morgens):
- `konkurrent`: 2026-07-29T15:46 → 2026-07-30T15:30:00+02:00
- `notiz-feierabend`: 2026-07-29T17:17 → 2026-07-30T17:30:00+02:00
- `notdienst-aufschlag`: 2026-07-30T07:27 → 2026-07-31T07:30:00+02:00

`status: ready` bleibt unverändert — die Dateien warten weiter auf den
Metricool-Login, damit sie tatsächlich eingeplant werden können.

**Wiederkehrendes Problem? Einschätzung:** Aktuell keine Evidenz für
Token-Ablauf — die Kette seit 28.07. sieht nach "nie autorisiert" aus, nicht
nach "war autorisiert, dann abgelaufen" (es gibt keinen einzigen
erfolgreichen Tick seit dem letzten manuellen Lauf am 29.07. 12:44).
Claude-Code speichert MCP-OAuth-Credentials nutzerweit auf der Platte, nicht
sessiongebunden — eine einmalige echte interaktive Anmeldung sollte daher
auch für die non-interactive launchd-Ticks reichen. Ob Metricools
Refresh-Token wirklich dauerhaft hält, lässt sich erst nach ein paar Tagen
Beobachtung sagen. Vorschlag, falls es doch wieder abreißt: `tick.sh` bei
"nicht autorisiert" eine sichtbare Benachrichtigung schicken (z. B.
`osascript -e 'display notification ...'`), statt dass es wie jetzt 2+ Tage
lang still vor sich hin scheitert, bis Ben zufällig nachfragt.

## Nachtrag 30.07.2026, 12:45 (Publikus, Login bestätigt + Nachtrag erledigt)

**Ben hat den Login erledigt.** Verifiziert per `getBrandSettings` (Brand
"Auralex", id 6521208, timezone Europe/Berlin, facebook/instagram verbunden)
und `getScheduledPosts` — beide liefen sauber. Metricool-MCP ist ab jetzt in
dieser Session voll funktionsfähig.

**Alle 5 liegen gebliebenen ready-Posts nachgezogen** (Ben-Wunsch: alle noch
heute), jeweils Reel + Story auf Facebook/Instagram, Status auf `scheduled`,
einzeln committet + gepusht:
- `notdienst-aufschlag` → 13:30
- `konkurrent` → 16:00
- `notiz-feierabend` → 18:30
- `eigene-zeit` → 20:00 (Nebenfund: vom Auto-Reel-Generator erzeugt, hatte
  denselben Blocker, war Ben nicht bekannt)
- `lieferschein-verschwindet` → 21:30 (gleicher Nebenfund)

**Ein sechster, ganz frisch generierter Post** (`entsorgung-nicht-berechnet`,
publish_at bereits wieder in der Vergangenheit) kam während der Bearbeitung
per Auto-Reel-Pipeline dazu — noch NICHT nachgezogen, mit Ben abzustimmen.

**Login hält vorerst:** kein erneuter Autorisierungsfehler während der
gesamten Session-Nutzung. Endgültige Aussage zur Refresh-Token-Lebensdauer
erst nach dem morgigen 07:00-Tick möglich (`out/tick.log` prüfen).
