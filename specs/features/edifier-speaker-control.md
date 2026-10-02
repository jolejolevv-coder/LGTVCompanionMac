## Goal
Die Edifier M90 direkt vom Mac aus steuern: echte Lautstärke über die
Tastatur und den Sub Out Pegel (Low, Medium, High), ohne Handy App.

## Background
Die Lautsprecher hängen optisch am TV, der TV kann ihre Lautstärke nicht
regeln. Bisher dämpft die App deshalb den Mac Ton (Software Volume). Die M90
haben aber einen eigenen Steuerkanal über Bluetooth LE, den die Handy App
EDIFIER ConneX nutzt. Das Protokoll ist von der Community dokumentiert
(github.com/kralonur/edifier-speakers-ble, MIT, `docs/edifier-m90-ble.md`).

Lesetest am 02.10.2026 gegen das Gerät des Nutzers (Firmware 1.5.1, die
Referenz beschreibt 2.5.1): Name, Lautstärke (Maximum 50), Sub Out und EQ
Preset antworten wie dokumentiert.

## Scope
- In scope: Verbindung per Bluetooth LE; Lautstärke lesen und setzen (0 bis
  50); Sub Out lesen und setzen; Lautstärketasten und Stummtaste; Abschnitt
  im Menü der Menüleiste; Schalter in den Settings; Rückfall auf Software
  Volume, wenn die Lautsprecher nicht erreichbar sind.
- Out of scope: Eingangswahl, Equalizer, Umbenennen, Ausschalten, Firmware
  Update; andere Edifier Modelle; Bluetooth als Tonweg.

## Acceptance criteria
- [x] Frames für Abfragen, Lautstärke und Sub Out stimmen Byte für Byte mit
      der Referenz überein (Tests).
- [x] Echte Antworten des Geräts werden geparst, falsche Prüfsumme, gekürzte
      und fremde Daten werden verworfen (Tests).
- [x] Lesen gegen das echte Gerät funktioniert (Testprogramm, 02.10.2026).
- [ ] Sub Out im Menü umschalten, Lautsprecher bestätigen den neuen Wert.
- [ ] Lautstärketasten ändern die Lautstärke der Lautsprecher, die Anzeige
      oben rechts zeigt den Wert.
- [ ] Stummtaste setzt auf 0 und stellt den alten Wert wieder her.
- [ ] Slider im Menü setzt die Lautstärke.
- [ ] Nach 20 s ohne Nutzung trennt die App, die Handy App kommt wieder dran.
- [ ] Sind die Lautsprecher nicht erreichbar, greifen die Tasten nach dem
      ersten Fehlversuch auf das Software Volume zurück.
- [ ] Übergabe: Dämpft das Software Volume beim ersten Verbinden, wandert die
      Dämpfung in die Lautsprecher, ohne dass es zwischendurch lauter wird.

Die offenen Punkte brauchen Ohr und Hand des Nutzers, Schreiben auf das Gerät
wurde bis zur Auslieferung bewusst nicht automatisch ausprobiert.

## Implementation plan
Phase 1: Spike als eigenes kleines Programm, nur lesen. Erledigt.
Phase 2: `Shared/EdifierProtocol.swift` (Frames, Parser, Tests) und
         `Shared/EdifierSpeakerController.swift` (Bluetooth, Verbindung bei
         Bedarf, Trennen nach Leerlauf). Abschnitt "Speakers" im Menü mit
         Lautstärke und Sub Out. Schalter in den Settings.
Phase 3: Lautstärketasten gehen zuerst an die Lautsprecher, sonst wie bisher.
         Übergabe der Software Dämpfung an die Lautsprecher.

## Design decisions
- Verbinden bei Bedarf, Trennen nach 20 s Leerlauf. Die Lautsprecher lassen
  nur einen Bluetooth LE Client zu. Eine Dauerverbindung würde die Handy App
  aussperren. Preis: Der erste Tastendruck nach einer Pause reagiert mit rund
  einer Sekunde Verzögerung.
- Die Kennung der Lautsprecher wird gespeichert, damit das Wiederverbinden
  ohne Suche auskommt. "Forget Speakers" löscht sie.
- Reihenfolge der Tasten: Lautsprecher, dann Software Volume, dann TV, dann
  macOS. Die Lautsprecher regeln für alle Quellen und ohne digitalen Verlust.
- Nach einem Fehlversuch 60 s Pause, in der die Tasten sofort an den Rückfall
  gehen, statt bei jedem Druck sechs Sekunden zu warten.
- 2 Einheiten je Tastendruck bei 50 Stufen, also 25 Schritte für den ganzen
  Bereich. Passt zu einem Drehregler.
- Stumm ist "Lautstärke 0 und alten Wert merken". Einen eigenen Befehl dafür
  nennt die Referenz nicht.
- Sub Out wird nach dem Setzen zurückgelesen. Eine Bestätigung allein belegt
  laut Referenz nicht, dass sich der Wert geändert hat.
- Opt in: ohne den Schalter in den Settings entsteht keine Bluetooth
  Verbindung und keine Abfrage der Freigabe.

## Risks
- Die Firmware des Nutzers (1.5.1) ist älter als die der Referenz. Lesen
  stimmt überein, Schreiben ist erst mit der Abnahme belegt.
- Das Koppeln der Lautsprecher in den Bluetooth Einstellungen von macOS ist
  nicht nötig und stellt die Lautsprecher auf den Eingang Bluetooth um.
- Der Lesetest meldete als Eingang `1D 01`, laut Referenz Bluetooth, obwohl
  der Ton über optisch läuft. Entweder stand der Eingang wirklich auf
  Bluetooth oder die Zuordnung weicht bei 1.5.1 ab. Die Eingangswahl ist
  deshalb nicht Teil dieses Features.

## Open questions
- Keine.
