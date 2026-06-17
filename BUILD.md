# LGTV Companion für macOS - Build-Anleitung

## Voraussetzungen

- macOS 13.0 (Ventura) oder neuer
- Xcode 15.0 oder neuer
- Swift 5.9 oder neuer

## Projektstruktur

```
LGTVCompanionMac/
├── App/                        # Haupt-SwiftUI-Anwendung
│   ├── LGTVCompanionApp.swift # App-Entry-Point
│   └── Views/                 # UI-Views
│       ├── ContentView.swift
│       ├── DeviceDetailView.swift
│       ├── DeviceScannerView.swift
│       ├── AddDeviceView.swift
│       └── SettingsView.swift
├── Daemon/                    # Hintergrund-Daemon
│   ├── main.swift
│   └── com.lgtvcompanion.daemon.plist
├── Shared/                    # Gemeinsame Logik
│   ├── WebOSClient.swift     # WebOS API Client
│   ├── WakeOnLAN.swift       # Wake-on-LAN
│   ├── DeviceDiscovery.swift # Netzwerk-Scanner
│   ├── PowerEventMonitor.swift # macOS Power Events
│   └── DeviceManager.swift   # Geräte-Verwaltung
└── README.md
```

## Xcode-Projekt erstellen

### Schritt 1: Neues Projekt erstellen

1. Öffne Xcode
2. Erstelle ein neues Projekt: **File → New → Project**
3. Wähle **macOS → App**
4. Projekteinstellungen:
   - Product Name: `LGTV Companion`
   - Team: Dein Development Team
   - Organization Identifier: `com.lgtvcompanion`
   - Interface: SwiftUI
   - Language: Swift
   - Use Core Data: Nein
   - Include Tests: Optional

### Schritt 2: Dateien hinzufügen

1. Lösche die automatisch erstellte `ContentView.swift`
2. Erstelle folgende Ordnerstruktur im Projekt:
   - `Views` (Group)
   - `Shared` (Group)
3. Füge alle Dateien aus diesem Repository zur entsprechenden Group hinzu

### Schritt 3: Daemon-Target erstellen

1. **File → New → Target**
2. Wähle **macOS → Command Line Tool**
3. Product Name: `LGTV Companion Daemon`
4. Language: Swift
5. Füge `Daemon/main.swift` zum Daemon-Target hinzu
6. Füge alle Files aus `Shared/` zu **beiden** Targets hinzu (App und Daemon)

### Schritt 4: Build Settings konfigurieren

#### Für beide Targets:

**Deployment Target:**
- macOS 13.0 oder höher

**Signing & Capabilities:**
- Aktiviere "Hardened Runtime"
- Füge folgende Capabilities hinzu:
  - Network (Client/Server)
  - Outgoing Connections (Client)

**Info.plist Einträge (nur Main App):**

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>LGTV Companion needs access to your local network to discover and control your LG WebOS TV.</string>

<key>NSBonjourServices</key>
<array>
    <string>_webos._tcp</string>
</array>

<key>LSUIElement</key>
<false/>
```

### Schritt 5: Dependencies linken

Beide Targets benötigen:
- `Foundation.framework`
- `Network.framework`
- `IOKit.framework`
- `ServiceManagement.framework` (für Launch at Login)

### Schritt 6: Daemon als Login Item einbetten

1. Im Main App Target, gehe zu **Build Phases**
2. Füge eine neue **Copy Files** Phase hinzu:
   - Destination: `Wrapper`
   - Subpath: `Contents/Library/LoginItems`
   - Füge `LGTV Companion Daemon.app` hinzu

## Build & Run

### Entwicklung

1. Wähle das **LGTV Companion** Scheme
2. Drücke **⌘R** zum Builden und Starten

### Daemon testen

Der Daemon startet automatisch, wenn Launch at Login aktiviert wird. Zum manuellen Testen:

```bash
# Daemon-Binary direkt starten
./DerivedData/.../LGTV\ Companion\ Daemon

# Logs ansehen
tail -f /tmp/com.lgtvcompanion.daemon.log
```

### Production Build

1. Wähle **Product → Archive**
2. Exportiere die App mit **Developer ID** Signierung
3. Distribuiere über:
   - Direct Download
   - Mac App Store (benötigt zusätzliche Anpassungen)
   - Homebrew Cask

## Code-Signierung

Für Distribution außerhalb des App Stores:

```bash
# App signieren
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Your Name" \
  "LGTV Companion.app"

# Notarisierung
xcrun notarytool submit LGTV\ Companion.zip \
  --apple-id your@email.com \
  --team-id TEAMID \
  --password app-specific-password \
  --wait

# Staple
xcrun stapler staple "LGTV Companion.app"
```

## Fehlerbehebung

### "Cannot find type 'NWProtocolWebSocket' in scope"

WebSocket-Support in Network.framework ist verfügbar ab macOS 13.0.
Stelle sicher, dass dein Deployment Target mindestens 13.0 ist.

### Daemon startet nicht

1. Überprüfe die Logs: `cat /tmp/com.lgtvcompanion.daemon.log`
2. Stelle sicher, dass der Daemon korrekt in der App eingebettet ist
3. Prüfe die Berechtigungen: `ls -la /Applications/LGTV\ Companion.app/Contents/Library/LoginItems/`

### TV wird nicht gefunden

1. Stelle sicher, dass TV und Mac im gleichen Netzwerk sind
2. Aktiviere "Local Network" Berechtigung in Systemeinstellungen
3. Prüfe Firewall-Einstellungen

### Wake-on-LAN funktioniert nicht

1. Aktiviere "Turn on via WiFi" in den TV-Einstellungen
2. Verwende eine statische IP-Adresse für den TV
3. Teste verschiedene WOL-Methoden im DeviceDetailView

## Entwicklungs-Tipps

### Live-Logging aktivieren

```swift
// In DeviceManager.swift
private func handlePowerEvent(_ event: PowerEvent) {
    print("Power event: \(event)")  // Debug-Log
    // ...
}
```

### SwiftUI Previews nutzen

Alle Views haben Preview-Provider. Nutze diese für schnelles UI-Prototyping:

```bash
⌥⌘P - Preview aktivieren
⌥⌘↵ - Preview im Canvas zeigen
```

### Debugging

1. Setze Breakpoints in Power Event Handlers
2. Nutze `po` im LLDB Debugger:
   ```
   po deviceManager.devices
   po client.isConnected
   ```

## Nächste Schritte

- [ ] App Icon hinzufügen (Assets.xcassets)
- [ ] Lokalisierung (Deutsch, Englisch)
- [ ] Crash Reporting integrieren
- [ ] Automatische Updates (Sparkle Framework)
- [ ] Mehr TV-Befehle hinzufügen (Volume, Input, etc.)
- [ ] Menu Bar App Option

## Ressourcen

- [LG WebOS API Dokumentation](https://github.com/chros73/pywebostv)
- [Apple Network Framework](https://developer.apple.com/documentation/network)
- [IOKit Power Management](https://developer.apple.com/documentation/iokit/iopwr_mgt)
- [Original Windows Version](https://github.com/JPersson77/LGTVCompanion)
