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

## ✅ Seit v1.0 dazugekommen (Stand 02.10.2026)

- [x] Menü in der Menüleiste im Stil des Kontrollzentrums
- [x] Tastatur Lautstärketasten steuern TV, Lautsprecher oder den Mac Ton
- [x] Software Volume für TV Ausgänge mit festem Pegel (optisch), mit Anzeige
- [x] Edifier M90 per Bluetooth: Lautstärke und Sub Out
- [x] Edifier M90: Klangwahl mit Techno und Hip-Hop, Equalizer, Eingang,
      Nachtmodus mit Zeitplan, Stromsparmodus (v1.2.0)
- [x] Status vom TV per Abo statt nur per Abfrage
- [x] MAC Adresse wird vom TV erfragt, Scanner zeigt nur steuerbare TVs
- [x] TV bleibt an, solange ein anderer Eingang läuft oder ein Video spielt
- [x] Auflösung und Skalierung der Displays im Menü
- [x] Lokale Signatur, damit Freigaben Updates überleben
- [x] Tests und Ausführung in der CI (125 Tests, Stand 28.10.2026)

## ✅ In 1.3.0 (28.10.2026, BAMA Phasen 1 bis 5)

Stabilität (Phase 1):
- [x] Gleichzeitige Befehle teilen sich einen connect und register (`TVSession`)
- [x] `isPaired` wird beim Verbindungsabbruch zurückgesetzt
- [x] Wiederholung eines Befehls nur bei vorübergehenden Fehlern
- [x] Sleep und Wake Automatik startet beim Programmstart, ohne offenes Fenster
- [x] Lautstärketaste ohne Core Audio Abfrage und ohne Speichern pro Tastendruck
- [x] Event Tap wird beim Stoppen invalidiert, kein `fatalError` mehr in der UI
- [x] Launch at login zeigt Fehler und behandelt die Freigabe durch den Nutzer
- [x] Timer Toleranz, weniger Schlüsselbund Schreibzugriffe, ein Scan Durchlauf je IP

Testbarkeit und Werkzeug (Phase 2):
- [x] Tastenweg als reine Funktion `VolumeKeyRoute` mit Tabellentest
- [x] Tests für Wake on LAN Paket, SSDP Parsing, Register und Request Nachrichten
- [x] `os.Logger` (`Log`) statt `print`, `DeviceManager.lastError` (noch ohne Anzeige)
- [x] `build-release.sh`: Prüfschritt für Signatur, Info.plist und Usage Strings,
      Abbruch ohne Zertifikat, `--install`, Build Nummer in `CFBundleVersion`
- [x] `CLAUDE.md` im Projekt

Offen aus dem BAMA Plan: Phase 3 (Bedienung), 4 (Tastatur, VoiceOver),
5 (Swift 6), siehe `specs/features/bama-review-improvements.md`.

Nicht mehr vorhanden: der separate Daemon. Die App läuft selbst in der
Menüleiste und übernimmt dessen Aufgabe.

## 🚧 In Arbeit

### Kritisch für Release
- [x] App Icon erstellen
- [x] Code Signing einrichten
- [ ] Notarisierung
- [x] DMG Installer erstellen
- [ ] Release auf GitHub
- [ ] README Screenshots

### Wichtige Features
- [x] Menu Bar App Modus (optional statt Dock Icon)
- [ ] Status Indikator (TV on/off im Menu Bar)
- [ ] Notifications für wichtige Events
- [ ] Crash Reporting
- [ ] Automatische Updates (Sparkle)

## 📋 Geplante Features (v1.1+)

### Erweiterte TV-Steuerung
- [x] Lautstärke-Steuerung
- [x] Input-Wechsel
- [ ] App-Launch (Netflix, YouTube, etc.)
- [ ] Cursor/Remote Control
- [ ] Screenshot-Funktion
- [x] TV Status Monitoring

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
- [x] Bessere Subnetz-Erkennung
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
- [x] WebSocket reconnection logic verbessern
- [x] Pairing Key Speicherung in Keychain
- [x] Error Handling bei Netzwerk-Timeouts
- [x] Display Configuration Monitor kann Race Conditions haben

### Mittlere Priorität
- [ ] SSDP Scanner timeout kann zu kurz sein
- [ ] XML Parser könnte robuster sein
- [ ] User Idle Monitor braucht Kalibrierung
- [ ] Launch at Login Implementierung vereinfachen

### Niedrige Priorität
- [ ] SwiftUI Preview warnings
- [ ] Code Comments auf Englisch
- [x] Unit Tests fehlen
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
- [x] Logger Framework statt print() (`os.Logger`, Phase 2)
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
- [x] GitHub Actions CI/CD

### Später
- [ ] Mac App Store
- [ ] Setapp
- [ ] MacUpdate
- [ ] Softonic

## 🧪 Testing

### Unit Tests
- [x] WebOSClient Tests (Statusauswertung, Register und Request Nachricht; Verbindung nur über Fake `TVTransport`)
- [x] WakeOnLAN Tests
- [x] DeviceDiscovery Tests (SSDP Antwort, Scan Filter; Scan selbst braucht ein Netz)
- [ ] PowerEventMonitor Tests
- [ ] DeviceManager Tests (teilweise: `VolumeKeyRoute`, Geräte Ablage; der Manager selbst nicht)

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
