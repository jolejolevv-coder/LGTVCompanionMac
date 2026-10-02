## Goal
Die Pairing Keys der TVs liegen im Schlüsselbund von macOS statt im Klartext in
der Einstellungsdatei der App.

## Background
Wer den Pairing Key hat, kann den TV steuern. Bisher stand er als Teil der
Geräteliste in `~/Library/Preferences/com.lgtvcompanion.mac.plist`: lesbar für
jeden Prozess des Nutzers und Teil jedes Backups. Der Schlüsselbund
verschlüsselt den Eintrag und bindet den Zugriff an die Signatur der App.

Voraussetzung war die feste Signatur (`scripts/create-signing-cert.sh`). Mit ad
hoc Signatur hätte der Schlüsselbund nach jedem Update nachgefragt.

## Scope
- In scope: Keys im Schlüsselbund ablegen, lesen, löschen; vorhandene Keys aus
  der Einstellungsdatei automatisch umziehen; Key beim Entfernen eines Geräts
  mitlöschen.
- Out of scope: iCloud Schlüsselbund und Abgleich zwischen Geräten; andere
  Einstellungen der App; TLS Zertifikat des TV merken (eigenes Thema).

## Acceptance criteria
- [x] Beim Speichern landet der Key im Schlüsselbund und fehlt in der Datei
      (Test).
- [x] Beim Laden wird der Key aus dem Schlüsselbund ergänzt, mehrere Geräte
      werden nicht vertauscht (Tests).
- [x] Eine alte Datei mit Key im Klartext wird erkannt und beim ersten Start
      umgezogen (Test).
- [x] Lehnt der Schlüsselbund das Schreiben ab, bleibt der Key in der Datei,
      das Pairing geht nicht verloren (Test).
- [x] Echter Schlüsselbund: Anlegen, Überschreiben, Lesen, Löschen und
      doppeltes Löschen funktionieren (Testprogramm mit Wegwerfeintrag,
      02.10.2026).
- [x] Installierte App: Nach dem ersten Start steht kein Key mehr in der
      Einstellungsdatei, der Eintrag im Schlüsselbund existiert.
- [ ] Der TV verlangt kein neues Pairing (Nutzer).

## Implementation plan
Phase 1: `Shared/PairingKeyStore.swift` mit `PairingKeyStoring`,
         `KeychainPairingKeyStore` und `DevicePersistence` (Kodieren ohne Key,
         Dekodieren mit Ergänzen und Erkennen alter Dateien).
Phase 2: `DeviceManager` nutzt beides in `saveDevices`, `loadDevices` und
         `removeDevice`.
Phase 3: Tests mit einem Schlüsselbund Ersatz im Speicher.

## Design decisions
- Ein Eintrag je Gerät, Dienst `com.lgtvcompanion.mac.pairing-key`, Konto ist
  die UUID des Geräts. So lässt sich ein einzelnes Gerät sauber entfernen.
- Der Key verlässt die Datei erst, nachdem er aus dem Schlüsselbund zurück
  gelesen wurde. Schlägt das fehl, bleibt die alte Ablage für dieses Gerät
  bestehen. Preis: Im Fehlerfall liegt der Key weiter im Klartext, dafür muss
  niemand neu koppeln.
- Klassischer Anmelde Schlüsselbund, nicht der Data Protection Schlüsselbund.
  Letzterer verlangt eine Berechtigung, die es nur mit Apple Entwicklerkonto
  gibt.
- Das Modell `WebOSDevice` bleibt unverändert, der Key wird nur beim Schreiben
  der Datei weggelassen. So ändert sich im Rest der App nichts.

## Risks
- Ein Build mit anderer Signatur (ad hoc, CI, neues Zertifikat) darf den
  Eintrag nicht ohne Nachfrage lesen. macOS zeigt dann einen Dialog. Wird er
  abgelehnt, verlangt der TV ein neues Pairing.
- Das ungenutzte Daemon Programm hätte dasselbe Problem.

## Open questions
- Keine.
