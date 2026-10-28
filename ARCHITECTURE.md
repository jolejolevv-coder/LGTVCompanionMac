# Architektur

Stand 28.10.2026, Version 1.3.0. Dieses Dokument beschreibt, was im Repo
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
| `VolumeKeyRoute.swift` | Wohin eine Lautstärketaste geht: Lautsprecher, Software Volume, TV, macOS |
| `SoftwareVolumeController.swift` | Mac Ton per Core Audio Tap dämpfen |
| `EdifierProtocol.swift` | Frames des Edifier Protokolls bauen und lesen |
| `EdifierSpeakerController.swift` | Bluetooth Verbindung zu den Lautsprechern |
| `SpeakerSound.swift` | Klangwahl, EQ Kurven (Techno, Hip-Hop), Zeitplan des Nachtmodus |
| `SpeakerAutomation.swift` | My EQ, Nachtmodus, Eingang beim Aufwachen |
| `DisplayControl.swift` | Auflösung und Skalierung der Displays |
| `Log.swift` | `os.Logger` je Bereich (tv, speakers, audio, app), Subsystem `com.lgtvcompanion.mac` |

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
| `Views/SpeakerSettingsView.swift` | Settings Tab für die Lautsprecher, Equalizer |

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

Entschieden wird in `VolumeKeyRoute.route` (reine Funktion, getestet), aufgerufen von `DeviceManager.handleMediaKey`, in dieser Reihenfolge:

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

## Threads und Concurrency

Das Paket baut im Swift 6 Sprachmodus (`swift-tools-version: 6.0`), der
Compiler prüft die Isolation vollständig. Schlüsselprinzip: Alles, was die
Oberfläche oder den Gerätestatus berührt, ist `@MainActor`. Alles, was auf
einer eigenen Queue läuft, ist `nonisolated` und gibt Ergebnisse über
`MainThread.async` oder `MainThread.asyncAfter` (`Shared/MainThread.swift`) an
den Hauptthread zurück. Diese Helfer nutzen `DispatchQueue.main` und
`MainActor.assumeIsolated`, damit die Reihenfolge der Aufrufe erhalten bleibt
(ein `Task { @MainActor in }` verspricht das nicht).

Zugrunde liegt eine Regel aus dem Swift 6 Wechsel: Ein Closure, das in einem
`@MainActor` Typ entsteht und an eine API geht, die es auf einer Hintergrund
queue ausführt, löst zur Laufzeit einen Trap aus. Solche Closures sind
`@Sendable` und betreten den Main Actor nur über `MainThread`. Ein direktes
`MainActor.assumeIsolated` steht nur dort, wo die Queue nachweislich die Main
Queue ist (Registrierung mit `queue: .main` oder Hauptrunloop).

### Isolation der Typen

| Typ | Isolation | Begründung |
|---|---|---|
| `DeviceManager`, `SpeakerAutomation`, `EdifierSpeakerController`, `SoftwareVolumeController`, `MediaKeyMonitor`, `PowerEventMonitor`, `UserIdleMonitor`, `DisplayConfigurationMonitor`, `DeviceDiscovery` | `@MainActor` | Halten veröffentlichten Zustand oder hängen an Hauptrunloop und Main Queue. Deinit über `isolated deinit` (braucht Swift 6.2, also Xcode 26 oder neuer). |
| `AppDelegate`, `VolumeHUD`, `VolumeHUDModel` | `@MainActor` | AppKit und SwiftUI. |
| `WebOSClient` | `@unchecked Sendable`, eigene serielle Queue | Jeder Zugriff auf veränderlichen Zustand läuft auf `queue`. Die veröffentlichten Werte `isConnected` und `isPaired` sind `@MainActor` und werden über `publishLinkState` gesetzt. Die Callbacks `onPairingKeyUpdated` und `onStatusUpdate` sind `@Sendable`. |
| `TVSession` | `actor` | Serialisiert Verbindungsversuche je Gerät. |
| Werttypen (`DeviceStatus`, `PowerEvent`, `EQCurve`, `NightSchedule` und weitere) | `Sendable` | Wandern zwischen Queues. |

### Callbacks und ihre Queue

| Callback | Läuft auf | Entscheidung |
|---|---|---|
| `NWConnection` State, Receive, Timeouts in `WebOSClient` | `WebOSClient.queue` | Bleibt dort, kein Main Actor Zugriff. Ergebnisse als `async`, Linkstatus über `MainThread.async`. |
| IOKit Power Callback (`IORegisterForSystemPower`) | Hauptrunloop | `MainActor.assumeIsolated`. |
| `NSWorkspace` Observer (Sleep, Wake, Screens) | `.main` | `MainActor.assumeIsolated`. |
| Timer in `UserIdleMonitor`, `SpeakerAutomation`, `DeviceManager`, `DeviceDiscovery` | Hauptrunloop | `MainActor.assumeIsolated`. |
| `CGEvent.tapCreate` Callback (`MediaKeyMonitor`) | Hauptrunloop | `MainActor.assumeIsolated` um `shouldSwallow`. |
| `CGDisplayRegisterReconfigurationCallback` | beliebiger Thread | Springt über `MainThread.async` auf den Main Actor. |
| Core Audio Listener Default Output (`SoftwareVolumeController`) | `.main` (bei der Registrierung angegeben) | `MainActor.assumeIsolated`. |
| Core Audio IOProc (`SoftwareVolumeController`) | `ioQueue`, Echtzeit | `nonisolated static func render`, kein Main Actor. Die Zeiger auf Ziel und aktuellen Gain sind `nonisolated(unsafe)` (siehe Kommentar im Code), gelesen wird ohne Sperre. |
| `CBCentralManager` und `CBPeripheral` Delegate (`EdifierSpeakerController`) | `.main` (Central mit `queue: .main`) | `@preconcurrency` Konformität, die Methoden laufen auf dem Main Actor. |
| Bonjour und SSDP Gruppe in `DeviceDiscovery` | `.main` | `MainActor.assumeIsolated`. |
| `URLSession` Completion in `DeviceDiscovery` | Hintergrund | `@Sendable`, baut das Ergebnis dort und springt über `MainThread` zurück. |
| `probeControlPort` Completion | `probeQueue` | `nonisolated static`, Ergebnis über `MainThread`. |
| `Task.detached` in `WakeOnLAN` und `MACAddressResolver` | Global Executor | Statische `nonisolated` Funktionen ohne Zustand. |
| `DispatchWorkItem` mit `asyncAfter` auf `DispatchQueue.main` | Main Queue | Stehen in `@MainActor` Typen. Die Closures sind dort isoliert und laufen auf der Main Queue. |

### Smoke Tests

`BackgroundMonitorSmokeTests` startet und stoppt die Monitore ohne Hardware
für etwa eineinhalb Sekunden: Idle Timer (löst mit Schwelle 0 wirklich aus),
Display Callback, Power Registrierung, `SpeakerAutomation` Timer und
`SoftwareVolumeController` ohne Tap. Nicht abgedeckt, weil sie eine
Berechtigung, Bluetooth oder einen TV brauchen: Event Tap der Medientasten,
CoreBluetooth, Verbindung des `WebOSClient`, Start des Audio Taps.

## Tests

`Tests/LGTVCompanionSharedTests` deckt die Logik ohne Hardware ab: Kurve und
Stufen der Lautstärke, Moduswahl, Edifier Frames, Auslesen der TV Meldungen,
MAC Erkennung, Ablage der Pairing Keys. Die CI führt sie bei jedem Push aus.

Nicht automatisch getestet ist alles, was echte Geräte braucht: Verbindung zum
TV, Audio Tap, Bluetooth, Tasten. Dafür stehen in den Specs und in `USAGE.md`
Schritte zur Abnahme von Hand.
