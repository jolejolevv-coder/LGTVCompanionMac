## Goal
Die App erfährt Änderungen am TV (Lautstärke, Stumm, Tonausgang, Power) sofort
vom TV selbst, statt sie alle 60 Sekunden abzufragen.

## Background
Bisher holte ein Timer den Status einmal pro Minute. Stellte man am TV den
Tonausgang um oder schaltete den Bildschirm aus, zeigte die App bis zu einer
Minute lang den alten Stand, und die Lautstärketasten gingen so lange an das
falsche Ziel. webOS kann Änderungen von sich aus melden: Eine Nachricht vom
Typ `subscribe` liefert sofort den aktuellen Stand und danach jede Änderung.

Probe am 02.10.2026 gegen den TV des Nutzers: Abos auf `audio/getVolume`,
`tvpower/power/getPowerState`, `applicationManager/getForegroundAppInfo` und
`apiadapter/audio/getSoundOutput` werden angenommen.

## Scope
- In scope: stehende Abos auf Lautstärke (enthält Stumm und `adjustVolume`)
  und Power; automatisches Neuabonnieren nach jedem Verbindungsaufbau;
  Übernahme in den veröffentlichten Status und in die Wahl des
  Lautstärkeziels.
- Out of scope: Abo auf den aktiven Eingang (wird nur kurz vor dem Ausschalten
  gebraucht und dort frisch abgefragt); Abschaffen der Abfrage alle 60 s.

## Acceptance criteria
- [x] Antworten der Abos werden geparst, verschachtelte und flache Form,
      fehlende Werte bleiben leer (Tests mit echter Antwort des TV).
- [x] Gegen den echten TV: 0,01 s nach dem Registrieren kommen Lautstärke und
      Power über das Abo an, eine normale Abfrage funktioniert daneben weiter
      (Testprogramm, 02.10.2026).
- [x] Nach jedem neuen Verbindungsaufbau wird neu abonniert (Abos hängen am
      Registrieren).
- [x] In der App vom Nutzer abgenommen (02.10.2026).

## Implementation plan
Phase 1: `WebOSClient`: Abos nach `registered` senden, Nachrichten mit den
         Abo Kennungen vor den normalen Antworten abfangen, `onStatusUpdate`.
         Parser als eigene Funktionen, von Abfrage und Abo gemeinsam genutzt.
Phase 2: `DeviceManager.applyStatusUpdate` führt die Meldung in den Status
         ein und ruft `noteVolumeAdjustable`.
Phase 3: Tests für die Parser.

## Design decisions
- Die Abfrage alle 60 s bleibt. Sie hält die Verbindung warm, was das
  Ausschalten vor dem Ruhezustand schnell macht, und fängt Firmware ab, die ein
  Abo ablehnt. Preis: weiter eine Anfrage pro Minute, dafür kein Rückschritt.
- Feste Abo Kennungen statt eines allgemeinen Abo Mechanismus. Es gibt genau
  zwei Abos, ein Register für beliebige wäre Vorratscode.
- Lehnt der TV ein Abo ab, passiert nichts weiter. Der Wert kommt dann wie
  bisher über die Abfrage.

## Open questions
- Keine.
