# 🚀 LGTV Companion für macOS - Quick Start

## Was ist das?

Eine vollständige, native macOS-Portierung der beliebten Windows-App LGTV Companion. Steuere deinen LG WebOS TV automatisch basierend auf dem Energiestatus deines Macs!

## ⚡ Schnellstart

### 1. Xcode-Projekt erstellen

```bash
# Öffne Xcode und erstelle ein neues macOS App Projekt
# Name: LGTV Companion
# Organization Identifier: com.lgtvcompanion
# Interface: SwiftUI
# Language: Swift
```

### 2. Dateien importieren

Projektstruktur in Xcode:

```
LGTV Companion/
├── App/
│   ├── LGTVCompanionApp.swift
│   └── Views/
│       ├── ContentView.swift
│       ├── DeviceDetailView.swift
│       ├── DeviceScannerView.swift
│       ├── AddDeviceView.swift
│       └── SettingsView.swift
├── Shared/
│   ├── WebOSClient.swift
│   ├── WakeOnLAN.swift
│   ├── DeviceDiscovery.swift
│   ├── PowerEventMonitor.swift
│   └── DeviceManager.swift
└── Daemon/
    ├── main.swift
    └── com.lgtvcompanion.daemon.plist
```

**Wichtig:** Alle `Shared/` Dateien müssen zu beiden Targets hinzugefügt werden!

### 3. Daemon-Target erstellen

1. File → New → Target → Command Line Tool
2. Name: `LGTV Companion Daemon`
3. `Daemon/main.swift` zum Daemon-Target hinzufügen
4. Alle `Shared/` Files zu beiden Targets hinzufügen

### 4. Build Settings

#### Deployment Target (beide Targets)
- macOS 13.0 oder höher

#### Frameworks linken (beide Targets)
- Foundation
- Network
- IOKit
- ServiceManagement

#### Capabilities (Main App)
- Hardened Runtime aktivieren
- Network → Incoming/Outgoing Connections

#### Info.plist (Main App)

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>LGTV Companion needs access to your local network to discover and control your LG WebOS TV.</string>

<key>NSBonjourServices</key>
<array>
    <string>_webos._tcp</string>
</array>
```

### 5. Build & Run

1. Wähle das "LGTV Companion" Scheme
2. Drücke ⌘R
3. Die App sollte starten! 🎉

## 🔧 Konfiguration

### TV vorbereiten

1. **Wichtig:** TV einschalten!
2. Gehe zu: Einstellungen → Verbindung → Mobile Verbindung
3. Aktiviere "TV einschalten über WiFi"
4. Notiere IP und MAC-Adresse (Einstellungen → Netzwerk)

### In der App

1. Klicke auf 🔍 zum Scannen **ODER** ➕ zum manuellen Hinzufügen
2. Gib die MAC-Adresse ein
3. Klicke "Pair Device" und bestätige auf dem TV
4. Teste mit "Test Power On/Off"
5. Aktiviere "Automatically manage this device"
6. Fertig! ✅

## 📁 Datei-Übersicht

### Core Funktionalität

| Datei | Beschreibung |
|-------|--------------|
| `WebOSClient.swift` | WebSocket-Kommunikation mit TV |
| `WakeOnLAN.swift` | Magic Packet senden |
| `DeviceDiscovery.swift` | SSDP-basierte Netzwerk-Suche |
| `PowerEventMonitor.swift` | macOS Power Events abfangen |
| `DeviceManager.swift` | Zentrale Verwaltung |

### UI

| Datei | Beschreibung |
|-------|--------------|
| `ContentView.swift` | Hauptfenster mit Device-Liste |
| `DeviceDetailView.swift` | Geräte-Konfiguration |
| `DeviceScannerView.swift` | Netzwerk-Scanner UI |
| `AddDeviceView.swift` | Manuelles Hinzufügen |
| `SettingsView.swift` | App-Einstellungen |

### Daemon

| Datei | Beschreibung |
|-------|--------------|
| `main.swift` | Hintergrund-Prozess |
| `.plist` | Launch Agent Konfiguration |

## 🎯 Features

✅ **Automatische Steuerung**
- TV geht aus beim Sleep/Shutdown
- TV geht an beim Wake

✅ **User Idle Mode**
- TV schaltet sich nach Inaktivität aus

✅ **Device Discovery**
- Automatische Netzwerk-Suche

✅ **Multiple TVs**
- Mehrere Geräte gleichzeitig verwalten

✅ **Native SwiftUI**
- Modern, performant, macOS-optimiert

## 🐛 Troubleshooting

### TV wird nicht gefunden
- ✅ TV eingeschaltet?
- ✅ Gleiche Netzwerk?
- ✅ "Local Network" Berechtigung erteilt?
- ✅ Firewall prüfen

### Wake-on-LAN funktioniert nicht
- ✅ "TV einschalten über WiFi" aktiviert?
- ✅ Statische IP verwenden!
- ✅ Andere WOL-Methode testen
- ✅ Bei WiFi: "Always Ready" aktivieren

### Mehr Details
Siehe `USAGE.md` für ausführliche Anleitung!

## 📚 Dokumentation

- `README.md` - Projekt-Übersicht
- `BUILD.md` - Detaillierte Build-Anleitung
- `USAGE.md` - Benutzerhandbuch
- `TODO.md` - Roadmap & bekannte Issues

## 🙏 Credits

Basiert auf dem originalen [LGTV Companion für Windows](https://github.com/JPersson77/LGTVCompanion) von Jörgen Persson.

## 📄 Lizenz

MIT License - siehe `LICENSE` Datei

---

**Viel Erfolg beim Bauen! 🎉**

Bei Fragen oder Problemen: GitHub Issues verwenden
