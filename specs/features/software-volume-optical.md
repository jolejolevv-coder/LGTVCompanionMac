## Goal
Die Lautstärketasten der Tastatur regeln den Mac Ton auch dann, wenn die
Lautsprecher optisch am TV hängen und der TV die Lautstärke nicht selbst
steuern kann.

## Background
Der TV meldet bei optischem Ausgang `soundOutput: external_optical` und
`adjustVolume: false`. Der optische Ausgang liefert festen Pegel, also bleiben
`ssap://audio/volumeUp`, `volumeDown` und `setVolume` wirkungslos. macOS bietet
für HDMI Ausgänge keinen eigenen Lautstärkeregler. Die einzige Stelle, an der
sich der Pegel ohne neue Hardware ändern lässt, ist der Mac Ton vor dem HDMI
Ausgang.

Gemessen am 02.10.2026: Ausgabegerät `LG TV SSCR2`, Transport HDMI, 2 Kanäle,
48 kHz, also PCM Stereo. Das ist die Voraussetzung, damit eine Dämpfung auf dem
Mac am Lautsprecher ankommt.

## Scope
- In scope: Software Volume für den Mac Ton auf dem HDMI Ausgang zum TV;
  Lautstärketasten und Mute Taste steuern diese Dämpfung; Slider im Menü der
  Menüleiste zeigt und setzt denselben Wert; automatische Wahl zwischen TV
  Lautstärke und Software Volume je nach Tonausgang des TV; Wert bleibt über
  Neustarts erhalten.
- Out of scope: Ton anderer Geräte am TV (Konsole auf anderem HDMI Eingang);
  Ansteuerung der Lautsprecher selbst; Bitstream Formate wie Dolby Digital
  (lassen sich nicht dämpfen); Equalizer oder Lautstärke je App.

## Acceptance criteria
Stand 02.10.2026. Abgehakt ist, was gemessen oder per Test belegt ist. Offene
Punkte brauchen die manuelle Abnahme am Lautsprecher (Schritte in `USAGE.md`).

- [x] Bei `adjustVolume: false` am TV regeln die Lautstärketasten den Pegel
      des Mac Tons in 16 Stufen (Logik per Test, Dämpfung im Spike gehört).
- [x] Bei `adjustVolume: true` (TV Lautsprecher, ARC) verhält sich die App wie
      bisher (Test der Moduswahl).
- [x] Mute Taste schaltet den Mac Ton stumm und wieder auf den alten Wert.
- [x] Der Slider im Menü zeigt im Software Modus den Software Wert und setzt ihn.
- [x] Der Wert übersteht einen Neustart der App (`UserDefaults`).
- [x] Beendet sich die App, läuft der Mac Ton ungedämpft weiter (Spike: Ton
      nach Prozessende normal).
- [x] Kein Echo, keine Rückkopplung (Spike, vom Nutzer gehört).
- [ ] Kein Knacken beim Ändern des Pegels (Rampe über 20 ms gebaut, noch
      nicht in der App gehört).
- [x] Zusätzliche Latenz unter 30 ms: gemessen rund 12,5 ms.
- [x] Wechselt das Standard Ausgabegerät weg vom TV, wird der Tap abgebaut und
      die Tasten gehen wieder an macOS (Listener plus Test der Moduswahl,
      Wechsel selbst noch nicht in der App ausprobiert).
- [ ] Verhalten nach Ruhezustand in der App geprüft.
- [x] Anzeige des Pegels oben rechts bei jedem Tastendruck (16 Segmente,
      Symbol für stumm), weil macOS im Software Modus kein eigenes Overlay
      zeigt. Nachtrag vom 02.10.2026 auf Wunsch nach dem ersten Test.

Abweichung vom ersten Entwurf: macOS bietet keine öffentliche Abfrage, ob die
Freigabe für System Audio erteilt ist. Die App kann eine fehlende Freigabe
deshalb nicht erkennen und die Tasten nicht vorsorglich an macOS durchlassen.
macOS fragt beim ersten Aufbau des Taps selbst. Wird abgelehnt, bleibt der Mac
unterhalb von 100 % stumm, bis die Freigabe erteilt oder die Funktion in den
Settings abgeschaltet wird. Bei 100 % läuft kein Tap, der Ton ist dann immer da.

## Implementation plan
Phase 1, Spike (Wegwerfcode im Scratchpad, kein Commit):
  Core Audio Process Tap (`AudioHardwareCreateProcessTap`, ab macOS 14.2) auf
  den gesamten System Ton mit `muteBehavior = .mutedWhenTapped`, eigener Prozess
  ausgeschlossen. Aggregate Device aus Tap und HDMI Ausgang, ein IOProc
  multipliziert die Samples mit dem Gain und schreibt sie auf den Ausgang.
  Ziel: beweisen, dass der Pegel am Lautsprecher sinkt, Latenz messen, Verhalten
  bei Absturz prüfen. Scheitert der Spike, wird der Ansatz verworfen statt
  variiert.

Phase 2, Kern:
  `Shared/SoftwareVolumeController.swift` mit einer Aufgabe: Tap aufbauen,
  Gain setzen, Tap abbauen. Gain Kurve als benannte Konstante (kubisch, damit
  die Stufen gleichmäßig klingen), Rampe über wenige Millisekunden gegen
  Knacken. Reagiert auf Wechsel des Standard Ausgabegeräts.
  `Package.swift` hebt das Minimum auf macOS 14.2.

Phase 3, Routing:
  `DeviceManager` liest `adjustVolume` aus `getVolume` und merkt sich je Gerät
  den Modus. `enqueueVolumeStep` und Mute gehen im Software Modus an den
  Controller statt an den TV. Wert in `UserDefaults`.

Phase 4, UI und Freigabe:
  Slider in `MenuBarView` an den aktiven Modus binden, kleiner Hinweis welcher
  Modus läuft. `NSAudioCaptureUsageDescription` in der `Info.plist` des Build
  Skripts, Abfrage der Freigabe beim ersten Bedarf. Schalter in den Settings
  zum Abschalten des Software Modus.

Phase 5, Tests und Doku:
  Test Target für die reine Logik (Gain Kurve, Stufen, Moduswahl aus der TV
  Antwort). Der Audio Pfad selbst wird manuell abgenommen, die Schritte dafür
  stehen in `USAGE.md`.

## Design decisions
- Process Tap statt virtuellem Audio Treiber. Ein HAL Plugin müsste mit
  Adminrechten nach `/Library/Audio` installiert werden und überlebt Updates
  schlecht. Der Tap läuft im Prozess der App. Preis: mindestens macOS 14.2 und
  eine weitere Freigabe.
- Moduswahl automatisch aus der Antwort des TV statt per Schalter. Der Nutzer
  soll nicht wissen müssen, welcher Ausgang gerade aktiv ist. Preis: eine
  Abfrage beim Verbinden und nach jedem Wechsel des Tonausgangs.
- Dämpfung nur nach unten, nie Verstärkung über 100 %. Verstärkung würde
  clippen.
- Digitale Dämpfung kostet Auflösung: bei sehr leiser Einstellung bleiben
  weniger Bits übrig. Bei 24 Bit über HDMI ist das unkritisch, deshalb den
  Regler am Lautsprecher auf einen sinnvollen Maximalpegel stellen und nur den
  Rest per Software regeln.

## Risks
- Die Freigabe für System Audio hängt wie Accessibility an der Signatur. Bei ad
  hoc Signatur bricht sie nach jedem Update. Ein lokales Signaturzertifikat
  würde beide Freigaben stabil machen, das ist eine eigene Entscheidung.
- Apps mit eigenem exklusivem Zugriff auf das Ausgabegerät (manche Player im
  Hog Mode) umgehen den Tap.
- Der Tap ist eine junge API. Verhalten nach Ruhezustand und nach Wechsel der
  Abtastrate wird im Spike gezielt geprüft.

## Open questions
- Mute: nur den Mac Ton stumm schalten, oder zusätzlich `setMute` an den TV
  schicken? Vorschlag: nur Mac Ton, weil der TV bei optischem Ausgang auch Mute
  nicht zuverlässig umsetzt.
- Signaturzertifikat jetzt mit erledigen, damit zwei Freigaben nicht nach
  jedem Update neu gesetzt werden müssen?
