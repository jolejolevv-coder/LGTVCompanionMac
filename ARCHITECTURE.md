# LGTV Companion macOS - Projekt-Architektur

## 📁 Ordner-Struktur

```
LGTVCompanionMac/
│
├── 📱 App/                          # Main Application (SwiftUI)
│   ├── LGTVCompanionApp.swift      # App Entry Point
│   └── Views/                       # UI Views
│       ├── ContentView.swift        # Main Window
│       ├── DeviceDetailView.swift   # Device Configuration
│       ├── DeviceScannerView.swift  # Network Scanner
│       ├── AddDeviceView.swift      # Manual Add Device
│       └── SettingsView.swift       # App Settings
│
├── 🔧 Shared/                       # Shared Logic (App + Daemon)
│   ├── WebOSClient.swift           # WebSocket API Client
│   ├── WakeOnLAN.swift             # Wake-on-LAN Magic Packets
│   ├── DeviceDiscovery.swift       # SSDP Network Scanner
│   ├── PowerEventMonitor.swift     # macOS Power Events
│   └── DeviceManager.swift         # Central Device Management
│
├── ⚙️ Daemon/                       # Background Service
│   ├── main.swift                   # Daemon Entry Point
│   └── com.lgtvcompanion.daemon.plist  # Launch Agent Config
│
├── 📖 Documentation/
│   ├── README.md                    # Project Overview
│   ├── QUICKSTART.md               # Quick Start Guide
│   ├── BUILD.md                     # Build Instructions
│   ├── USAGE.md                     # User Manual
│   └── TODO.md                      # Roadmap & Issues
│
├── Package.swift                    # Swift Package Manager
└── LICENSE                          # MIT License
```

## 🏗️ Architektur-Diagramm

```
┌─────────────────────────────────────────────────────────┐
│                    LGTV Companion                       │
│                     (Main App)                          │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │  SwiftUI     │  │   Settings   │  │   Scanner    │ │
│  │  Interface   │  │      UI      │  │      UI      │ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘ │
│         │                 │                 │          │
│         └─────────────────┼─────────────────┘          │
│                           │                            │
│                    ┌──────▼───────┐                    │
│                    │ DeviceManager│                    │
│                    └──────┬───────┘                    │
│                           │                            │
└───────────────────────────┼────────────────────────────┘
                            │
                ┌───────────┴───────────┐
                │                       │
    ┌───────────▼──────────┐ ┌─────────▼────────────┐
    │   Shared Framework   │ │  Launch Agent/Daemon │
    │                      │ │                      │
    │ ┌──────────────────┐ │ │  ┌────────────────┐ │
    │ │ WebOSClient      │ │ │  │ PowerMonitor   │ │
    │ │ - WebSocket API  │ │ │  │ - Sleep/Wake   │ │
    │ │ - Pairing        │ │ │  │ - Shutdown     │ │
    │ │ - Commands       │ │ │  │ - Idle detect  │ │
    │ └──────────────────┘ │ │  └────────────────┘ │
    │                      │ │                      │
    │ ┌──────────────────┐ │ │  Auto-manages TVs   │
    │ │ WakeOnLAN        │ │ │  based on events    │
    │ │ - Magic Packet   │ │ │                      │
    │ │ - UDP Broadcast  │ │ └──────────────────────┘
    │ └──────────────────┘ │           │
    │                      │           │
    │ ┌──────────────────┐ │           │
    │ │ DeviceDiscovery  │ │           │
    │ │ - SSDP Scanner   │ │           │
    │ │ - mDNS          │ │           │
    │ └──────────────────┘ │           │
    └──────────────────────┘           │
              │                        │
              │                        │
    ┌─────────▼────────────────────────▼─────┐
    │         LG WebOS TV (Network)          │
    │  ┌──────────────┐  ┌──────────────┐   │
    │  │ WebSocket    │  │ Wake-on-LAN  │   │
    │  │ Port 3000    │  │ Port 9       │   │
    │  └──────────────┘  └──────────────┘   │
    └────────────────────────────────────────┘
```

## 🔄 Datenfluss

### 1. Device Discovery
```
User clicks "Scan"
    ↓
DeviceDiscovery.startScan()
    ↓
Send SSDP M-SEARCH multicast
    ↓
Receive SSDP responses
    ↓
Parse device info (IP, Name, Model)
    ↓
Display in DeviceScannerView
```

### 2. Device Pairing
```
User clicks "Pair Device"
    ↓
WebOSClient.connect()
    ↓
Open WebSocket to TV:3000
    ↓
WebOSClient.register()
    ↓
Send pairing request
    ↓
User accepts on TV
    ↓
Receive pairing key
    ↓
Save to UserDefaults
```

### 3. Power On
```
Power Event detected
    ↓
DeviceManager.powerOnDevice()
    ↓
WakeOnLAN.wake()
    ↓
Create magic packet (6×0xFF + 16×MAC)
    ↓
Send UDP broadcast
    ↓
TV receives and powers on
```

### 4. Power Off
```
Power Event detected
    ↓
DeviceManager.powerOffDevice()
    ↓
WebOSClient.connect()
    ↓
WebOSClient.powerOff()
    ↓
Send "ssap://system/turnOff" command
    ↓
TV receives and powers off
```

## 🎯 Component Responsibilities

### App Layer
| Component | Verantwortung |
|-----------|---------------|
| ContentView | Haupt-UI, Device-Liste |
| DeviceDetailView | Device-Konfiguration |
| DeviceScannerView | Netzwerk-Scan UI |
| SettingsView | App-Einstellungen |

### Business Logic Layer
| Component | Verantwortung |
|-----------|---------------|
| DeviceManager | Zentrale Koordination |
| WebOSClient | TV-Kommunikation |
| WakeOnLAN | Magic Packet versenden |
| DeviceDiscovery | Netzwerk-Scanner |
| PowerEventMonitor | System Events |

### Daemon Layer
| Component | Verantwortung |
|-----------|---------------|
| Launch Agent | Background Process |
| PowerEventMonitor | Event Monitoring |
| DeviceManager | Auto-Steuerung |

## 🔐 Security & Permissions

### Required Permissions
```
✅ Local Network Access (NSLocalNetworkUsageDescription)
✅ Bonjour Services (_webos._tcp)
✅ Hardened Runtime
```

### Data Storage
```
UserDefaults:
├── devices                    # Array<WebOSDevice>
├── settings                   # [String: Any]
└── pairingKey_<deviceID>     # String (pro Device)

Future: Keychain für sensible Daten
```

## 🧪 Testing Strategy

### Unit Tests
```
✓ WebOSClient
  - Connection handling
  - Message parsing
  - Error handling

✓ WakeOnLAN
  - MAC parsing
  - Packet creation
  - Network sending

✓ DeviceManager
  - Device CRUD
  - Event handling
  - Persistence
```

### Integration Tests
```
✓ End-to-End Pairing
✓ Power Event Flow
✓ Multi-Device Scenarios
```

### UI Tests
```
✓ Device Add Flow
✓ Scanner Flow
✓ Settings Changes
```

## 📊 Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| App Launch | < 1s | Cold start |
| Device Discovery | < 5s | SSDP timeout |
| Power On | < 3s | WOL + boot time |
| Power Off | < 1s | WebSocket command |
| Memory | < 50MB | Idle state |
| Battery Impact | Minimal | Background daemon |

## 🚀 Deployment Flow

```
Developer
    ↓
Build in Xcode
    ↓
Archive
    ↓
Code Sign (Developer ID)
    ↓
Notarize (Apple)
    ↓
Create DMG
    ↓
Upload to GitHub Releases
    ↓
User Downloads
    ↓
Install to /Applications
    ↓
Launch & Enjoy!
```
