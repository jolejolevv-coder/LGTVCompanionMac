# Architektur

Stand 02.10.2026, Version 1.1.0. Dieses Dokument beschreibt, was im Repo
tatsächlich vorhanden ist. Wie man baut, steht in `BUILD.md`, wie man die App
benutzt, in `USAGE.md`, die Begründung einzelner Features in `specs/features/`.

## Überblick

Eine einzige App, die in der Menüleiste lebt und zusätzlich ein Fenster zur
Einrichtung hat. Sie hält eine Verbindung zum LG TV, reagiert auf Ereignisse
des Mac (Ruhezustand, Aufwachen, Leerlauf, Lautstärketasten) und steuert
daraufhin TV, Lautsprecher oder den Ton des Mac.

```
┌──────────────────────────── App (SwiftUI) ────────────────────────────┐
│  Menü in der Menüleiste     Fenster (Geräte, Settings)     Anzeige    │
└───────────────┬───────────────────────────────────────────────────────┘
                │ beobachtet und ruft auf
┌───────────────▼──────────── DeviceManager ────────────────────────────┐
│  Geräteliste, Status, Automatik, Wahl des Lautstärkeziels, Settings   │
└──┬──────────┬───────────┬────────────┬───────────────┬────────────────┘
   │          │           │            │               │
WebOSClient  PowerEvent  MediaKey   SoftwareVolume   EdifierSpeaker
(TV, WLAN)   Monitor     Monitor    Controller       Controller
             (IOKit)     (Tasten)   (Core Audio)     (Bluetooth LE)
```

Es gibt zwei Module: `LGTVCompanionShared` (alles ohne Oberfläche, mit Tests)
und `LGTVCompanionApp` (SwiftUI). Externe Abhängigkeiten gibt es keine.

## Module

### Shared

| Datei | Aufgabe |
|---|---|
| `DeviceManager.swift` | Zentrale: Geräte, veröffentlichter Status, Automatik, Routing der Tasten, Settings |
| `WebOSClient.swift` | WebSocket Verbindung zum TV, Pairing, Befehle, Status Abos |
| `PairingKeyStore.swift` | Pairing Keys im Schlüsselbund, Lesen und Schreiben der Geräteliste |
| `DeviceDiscovery.swift` | TVs per SSDP finden, nur steuerbare anzeigen |
| `MACAddressResolver.swift` | MAC des TV per SSDP erfragen |
| `WakeOnLAN.swift` | Magic Packet senden, Adressen prüfen |
| `PowerEventMonitor.swift` | Ruhezustand, Aufwachen, Leerlauf, Displaywechsel |
| `DisplaySleepAssertions.swift` | Welche App hält gerade den Bildschirm wach (Videowiedergabe) |
| `MediaKeyMonitor.swift` | Lautstärketasten abfangen |
| `SoftwareVolume.swift` | Rechenregeln: Kurve, Stufen, Moduswahl |
| `SoftwareVolumeController.swift` | Mac Ton per Core Audio Tap dämpfen |
| `EdifierProtocol.swift` | Frames des Edifier Protokolls bauen und lesen |
| `EdifierSpeakerController.swift` | Bluetooth Verbindung zu den Lautsprechern |
| `DisplayControl.swift` | Auflösung und Skalierung der Displays |

### App

| Datei | Aufgabe |
|---|---|
| `LGTVCompanionApp.swift` | Einstieg, Szenen, Verhalten beim Herunterfahren |
| `AppInfo.swift` | Version und Links |
| `VolumeHUD.swift` | Anzeige des Pegels oben rechts |
| `Views/MenuBarView.swift` | Menü in der Menüleiste |
| `Views/MenuComponents.swift` | Bausteine des Menüs (Karten, Regler, Knöpfe) |
| `Views/ContentView.swift`, `DeviceDetailView.swift` | Fenster mit Geräteliste und Details |
| `Views/DeviceScannerView.swift`, `AddDeviceView.swift` | TV hinzufügen |
| `Views/SettingsView.swift` | Settings |

## Verbindung zum TV

- WebSocket über TLS auf Port 3001. Der unverschlüsselte Port 3000 antwortet
  auf aktueller Firmware nicht mehr und dient nur als Rückfall.
- Das Zertifikat des TV ist selbst signiert und wird akzeptiert.
- TLS ist auf Version 1.2 begrenzt. Mit 1.3 hängt der Handshake des TV.
- Die Verbindung muss über eine URL (`wss://…`) aufgebaut werden. Mit Host und
  Port getrennt sendet Network.framework keinen brauchbaren Upgrade, der TV
  ignoriert ihn.
- Nach jedem Registrieren abonniert der Client Lautstärke und Power. Der TV
  meldet Änderungen dann von sich aus. Zusätzlich fragt die App alle 60 s ab,
  das hält die Verbindung warm.
- Bei einem Fehler wird einmal neu verbunden und der Befehl wiederholt.

Alle Zustände des Clients (offene Anfragen, Pairing, Verbindung) liegen auf
einer seriellen Queue.

## Wohin ein Druck auf die Lautstärketaste geht

Entschieden wird in `DeviceManager.handleMediaKey`, in dieser Reihenfolge:

1. **Lautsprecher**, wenn die Bluetooth Steuerung eingeschaltet ist und sie
   nicht gerade als unerreichbar gelten. Regelt im Lautsprecher selbst.
2. **Software Volume**, wenn der TV meldet, dass er die Lautstärke nicht ändern
   kann (`adjustVolume: false`, etwa bei optischem Ausgang), und der Mac Ton an
   ein Display geht. Dämpft den Mac Ton.
3. **macOS**, wenn der TV nicht regeln kann und der Ton woanders hingeht
   (Kopfhörer). Die Taste wird dann nicht abgefangen.
4. **TV**, in allen übrigen Fällen.

Fängt die App die Taste ab, zeigt `VolumeHUD` den Pegel, weil macOS dann kein
eigenes Overlay einblendet.

## Automatik

`PowerEventMonitor` meldet Ereignisse an `DeviceManager`:

| Ereignis | Reaktion |
|---|---|
| Mac geht schlafen, Display aus, Leerlauf | TV aus (Bildschirm aus oder ganz, je Gerät) |
| Mac wacht auf, Aktivität | TV an, erst per Befehl, sonst per Wake on LAN |
| Herunterfahren, Neustart | TV ganz aus |

Vor dem Ausschalten prüft die App zwei Ausnahmen: Zeigt der TV einen anderen
Eingang als den des Mac, bleibt er an. Hält eine freigegebene App den
Bildschirm wach (Video), gilt der Mac nicht als im Leerlauf.

Der Ruhezustand wird so lange verzögert, bis der Befehl beim TV angekommen ist,
höchstens 20 Sekunden.

## Daten

| Was | Wo |
|---|---|
| Geräteliste ohne Pairing Keys | `UserDefaults`, Schlüssel `lgtvcompanion.devices` |
| Pairing Keys | Schlüsselbund, Dienst `com.lgtvcompanion.mac.pairing-key`, ein Eintrag je Gerät |
| Settings | `UserDefaults`, Schlüssel `lgtvcompanion.settings` |
| Lautsprecher (an oder aus, Kennung) | `UserDefaults`, Schlüssel `lgtvcompanion.speakers.*` |

## Threads

- Oberfläche und veröffentlichter Status: Hauptthread.
- `WebOSClient`: eigene serielle Queue, Ergebnisse gehen per `async` zurück.
- `SoftwareVolumeController`: Der Audio Callback läuft auf einem Echtzeitthread.
  Er liest nur einen Zielwert, ohne Sperre und ohne Speicher anzufordern.
- `EdifierSpeakerController`: Bluetooth Callbacks auf dem Hauptthread.

`DeviceManager` ist kein Actor. Zugriffe auf veröffentlichte Werte aus
Hintergrundaufgaben laufen über `MainActor.run`. Die Compiler Warnungen zu
`Sendable` in `WebOSClient` sind bekannt und betreffen Zugriffe, die über die
serielle Queue laufen.

## Tests

`Tests/LGTVCompanionSharedTests` deckt die Logik ohne Hardware ab: Kurve und
Stufen der Lautstärke, Moduswahl, Edifier Frames, Auslesen der TV Meldungen,
MAC Erkennung, Ablage der Pairing Keys. Die CI führt sie bei jedem Push aus.

Nicht automatisch getestet ist alles, was echte Geräte braucht: Verbindung zum
TV, Audio Tap, Bluetooth, Tasten. Dafür stehen in den Specs und in `USAGE.md`
Schritte zur Abnahme von Hand.
