# LGTV Companion macOS - TODO & Roadmap

## ✅ Fertiggestellt (v1.0)

- [x] Basis-Projektstruktur
- [x] WebOS WebSocket Client
- [x] Wake-on-LAN Implementation
- [x] Power Event Monitoring (Sleep/Wake/Shutdown)
- [x] Device Discovery (SSDP)
- [x] User Idle Detection
- [x] SwiftUI Main App
- [x] Device Management (Add/Remove/Configure)
- [x] Pairing Flow
- [x] Launch Agent/Daemon
- [x] Settings UI
- [x] Auto-manage Toggle
- [x] Test Functions

## 🚧 In Arbeit

### Kritisch für Release
- [ ] App Icon erstellen
- [ ] Code Signing einrichten
- [ ] Notarisierung
- [ ] DMG Installer erstellen
- [ ] Release auf GitHub
- [ ] README Screenshots

### Wichtige Features
- [ ] Menu Bar App Modus (optional statt Dock Icon)
- [ ] Status Indikator (TV on/off im Menu Bar)
- [ ] Notifications für wichtige Events
- [ ] Crash Reporting
- [ ] Automatische Updates (Sparkle)

## 📋 Geplante Features (v1.1+)

### Erweiterte TV-Steuerung
- [ ] Lautstärke-Steuerung
- [ ] Input-Wechsel
- [ ] App-Launch (Netflix, YouTube, etc.)
- [ ] Cursor/Remote Control
- [ ] Screenshot-Funktion
- [ ] TV Status Monitoring

### Verbesserungen
- [ ] Mehrsprachigkeit (DE, EN, FR, ES)
- [ ] Dark/Light Mode Icons
- [ ] Animierte UI-Übergänge
- [ ] Erweiterte Logs mit Viewer
- [ ] Export/Import von Konfigurationen
- [ ] Backup/Restore Settings

### Automatisierung
- [ ] Zeitbasierte Regeln (z.B. "TV um 22:00 ausschalten")
- [ ] Shortcuts App Integration
- [ ] AppleScript Support
- [ ] Szenen (mehrere Actions auf einmal)
- [ ] Bedingte Automatisierungen

### Netzwerk
- [ ] mDNS/Bonjour Discovery
- [ ] IPv6 Support
- [ ] Bessere Subnetz-Erkennung
- [ ] VPN-Unterstützung
- [ ] Proxy-Konfiguration

### Performance
- [ ] Connection Pooling
- [ ] Async/Await Optimierungen
- [ ] Batterie-Optimierungen
- [ ] Memory Leak Tests
- [ ] Startup Time Optimierung

## 🐛 Bekannte Issues

### Hohe Priorität
- [ ] WebSocket reconnection logic verbessern
- [ ] Pairing Key Speicherung in Keychain
- [ ] Error Handling bei Netzwerk-Timeouts
- [ ] Display Configuration Monitor kann Race Conditions haben

### Mittlere Priorität
- [ ] SSDP Scanner timeout kann zu kurz sein
- [ ] XML Parser könnte robuster sein
- [ ] User Idle Monitor braucht Kalibrierung
- [ ] Launch at Login Implementierung vereinfachen

### Niedrige Priorität
- [ ] SwiftUI Preview warnings
- [ ] Code Comments auf Englisch
- [ ] Unit Tests fehlen
- [ ] UI Tests fehlen

## 📚 Dokumentation TODO

- [ ] API Dokumentation (Jazzy/DocC)
- [ ] Video Tutorial aufnehmen
- [ ] FAQ erstellen
- [ ] Troubleshooting Guide erweitern
- [ ] Contributing Guidelines
- [ ] Code of Conduct

## 🔧 Technische Schulden

- [ ] Proper Error Types statt NSError
- [ ] Logger Framework statt print()
- [ ] Dependency Injection
- [ ] Repository Pattern für Persistence
- [ ] MVVM refactoring
- [ ] Protocol-basierte Architektur

## 🎯 Langfristige Ziele

### v2.0 Vision
- [ ] HomeKit Integration
- [ ] Home Assistant Integration
- [ ] Web Interface (optional)
- [ ] iOS/iPadOS Companion App
- [ ] watchOS Companion App
- [ ] Command Line Tool
- [ ] Python Library für Scripting
- [ ] Plugins/Extensions System

### Community
- [ ] Discord/Slack Channel
- [ ] GitHub Discussions aktivieren
- [ ] Contributor Guidelines
- [ ] Beta Testing Programm
- [ ] Donation/Sponsorship Setup

## 📦 Distribution

### Sofort
- [x] GitHub Releases
- [ ] Homebrew Cask
- [ ] GitHub Actions CI/CD

### Später
- [ ] Mac App Store
- [ ] Setapp
- [ ] MacUpdate
- [ ] Softonic

## 🧪 Testing

### Unit Tests
- [ ] WebOSClient Tests
- [ ] WakeOnLAN Tests
- [ ] DeviceDiscovery Tests
- [ ] PowerEventMonitor Tests
- [ ] DeviceManager Tests

### Integration Tests
- [ ] End-to-End Pairing Flow
- [ ] Power Event Handling
- [ ] Multi-Device Scenarios
- [ ] Network Failure Recovery

### UI Tests
- [ ] Device Add Flow
- [ ] Settings Änderungen
- [ ] Scanner Flow
- [ ] Error States

## 📊 Metriken & Analytics (Optional, Privacy-first)

- [ ] Anonyme Nutzungsstatistiken
- [ ] Crash Reports (opt-in)
- [ ] Feature Usage Tracking
- [ ] Performance Metriken

## 💬 Feedback von Beta-Testern

- [ ] Beta Testing Gruppe finden
- [ ] Feedback-Formular erstellen
- [ ] Issue Template für Bug Reports
- [ ] Feature Request Template

## Prioritäten

### P0 (Blocker für v1.0)
1. App Icon
2. Code Signing
3. DMG Installer
4. Basic Testing

### P1 (Nice-to-have für v1.0)
1. Menu Bar App Modus
2. Notifications
3. Bessere Fehlerbehandlung

### P2 (v1.1)
1. Erweiterte TV-Steuerung
2. Lokalisierung
3. Automatische Updates

### P3 (v2.0+)
1. HomeKit Integration
2. iOS App
3. Web Interface
