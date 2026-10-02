## Goal
Klang, Eingang und einen Nachtmodus der Edifier M90 vom Mac aus steuern,
samt eigenem Equalizer und fertigen Kurven für Techno und Hip-Hop.

## Background
Baut auf `edifier-speaker-control.md` auf. Dasselbe Protokoll kennt neben
Lautstärke und Sub Out auch Eingangswahl, vier Klang Presets und einen
Equalizer mit neun Bändern (62 Hz bis 16 kHz, je ±3 dB in Schritten von 0,5).
Die Lautsprecher haben genau einen frei belegbaren Platz ("Custom").

## Scope
- In scope: Eingang wählen; Klang wählen aus Classic, Monitor, Dynamic
  (eingebaut) sowie Techno, Hip-Hop und My EQ (von der App in den Custom Platz
  geschrieben); Equalizer mit neun Reglern für My EQ; Nachtmodus mit
  Lautstärkegrenze und Sub Pegel, von Hand und nach Zeitplan; Eingang beim
  Aufwachen des Mac setzen.
- Out of scope: Tastenkürzel für Nachtmodus oder Klang; frei definierbare
  Szenen; Klangwechsel im Nachtmodus; Ausschalten der Lautsprecher (kein
  bekannter Befehl zum Einschalten); Ausschalttimer, Stromsparmodus,
  Hinweiston, Multipoint, Codec.

## Acceptance criteria
- [x] Frames für Eingang, Preset und EQ Band stimmen mit der Referenz überein,
      Antworten des echten Geräts werden geparst, fremde Layouts verworfen
      (Tests).
- [x] Schreiben auf dem Gerät des Nutzers (Firmware 1.5.1) belegt: Techno
      Kurve geschrieben und identisch zurückgelesen, Preset auf Classic
      gewechselt und bestätigt, Eingang gesetzt, danach der Ausgangszustand
      exakt wiederhergestellt (Testprogramm, 02.10.2026).
- [x] Eine Custom Kurve, die keine der App ist, wird als My EQ übernommen und
      geht durch die Wahl von Techno oder Hip-Hop nicht verloren (beim Nutzer:
      +0,5 dB bei 62 Hz).
- [x] Zeitplan über Mitternacht und innerhalb eines Tages (Tests).
- [x] Einstellungen überstehen einen Neustart, die Lautstärkegrenze gilt
      sofort wieder (Tests).
- [x] Menü und Settings Tab gerendert und per Bildschirmfoto geprüft.
- [ ] Vom Nutzer gehört: Techno und Hip-Hop klingen wie gewünscht.
- [ ] Nachtmodus von Hand: Grenze greift bei Tasten und Regler, Sub wechselt,
      Ausschalten stellt den alten Sub Pegel wieder her.
- [ ] Nachtmodus nach Zeitplan schaltet zur eingestellten Zeit.
- [ ] Eingang nach dem Aufwachen des Mac.

## Implementation plan
Phase 1: Protokoll (`EdifierProtocol`) und reine Logik (`SpeakerSound`), Tests.
Phase 2: `EdifierSpeakerController`: Eingang, Preset, Kurve in Abständen von
         80 ms schreiben, Lautstärkegrenze.
Phase 3: `SpeakerAutomation`: Klangwahl, My EQ, Nachtmodus, Zeitplan, Wake.
Phase 4: Menü (Sound, Input, Night mode) und Settings Tab "Speakers" mit
         Equalizer.

## Design decisions
- Der aktuelle Klang wird aus dem abgeleitet, was die Lautsprecher melden, und
  nicht separat gespeichert. So stimmt die Anzeige auch, wenn jemand in der
  Handy App etwas ändert.
- Kurven werden Band für Band mit 80 ms Abstand geschrieben. Ohne Abstand
  gehen Befehle verloren. Während des Schreibens wird ein gelesener
  Zwischenstand nicht als My EQ übernommen.
- Techno: +3 und +2 dB im Bass, untere Mitten um 1 dB zurück, Höhen bis
  +2,5 dB. Hip-Hop: +3, +2,5 und +1 dB im Bass und Oberbass, Mitten fast
  neutral, leichte Präsenz, weiche Höhen. Beide nutzen den Bereich von ±3 dB
  aus, mehr lässt der Lautsprecher nicht zu.
- Der Nachtmodus setzt den Sub Pegel einmal beim Einschalten. Danach darf man
  ihn von Hand ändern, ohne dass die App ihn zurückdreht. Die Lautstärkegrenze
  gilt dagegen durchgehend.
- Der Zeitplan schaltet nur an seinen Kanten. Wer nachts von Hand ausschaltet,
  bleibt bis zum nächsten Abend ungestört.
- Der Klang bleibt im Nachtmodus unverändert. Ein automatischer Klangwechsel
  um 22 Uhr wäre überraschend.
- Beim Aufwachen wird der Eingang erst gelesen und nur bei Abweichung gesetzt.

## Risks
- Die Kurven für Techno und Hip-Hop sind nach Erfahrungswerten gewählt und
  nicht an diesen Lautsprechern mit Subwoofer eingemessen.
- Zusammen mit Sub Out auf High kann +3 dB bei 62 Hz zu viel sein.

## Open questions
- Tastenkürzel für den Nachtmodus: welches Kürzel?
