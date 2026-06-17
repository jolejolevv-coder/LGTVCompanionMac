# LGTV Companion für macOS - Benutzerhandbuch

## Installation

### Voraussetzungen

Bevor du LGTV Companion installierst, stelle sicher, dass:

1. **Dein LG TV eingeschaltet ist** und mit dem Netzwerk verbunden ist
2. **"TV einschalten über WiFi" aktiviert ist:**
   - Gehe zu: Einstellungen → Verbindung → Mobile Verbindung → TV einschalten mit Mobilgerät
   - Aktiviere "TV einschalten über WiFi"
   - ⚠️ Dies ist **auch bei Ethernet-Verbindung notwendig**!
3. **Dein TV eine statische IP-Adresse hat** (empfohlen):
   - Konfiguriere eine DHCP-Reservation in deinem Router
   - Notiere dir die IP-Adresse deines TVs

### App installieren

1. Lade die neueste Version von den [Releases](https://github.com/yourusername/LGTVCompanionMac/releases) herunter
2. Öffne die `.dmg` Datei
3. Ziehe `LGTV Companion.app` in den Programme-Ordner
4. Starte die App

## Erste Einrichtung

### Schritt 1: Gerät hinzufügen

Du hast zwei Möglichkeiten:

#### Option A: Automatische Erkennung (empfohlen)

1. Klicke auf das **Lupensymbol** in der Toolbar
2. Warte, bis dein TV erkannt wird (ca. 5 Sekunden)
3. Trage die MAC-Adresse deines TVs ein
   - Diese findest du in: TV Einstellungen → Netzwerk → Status
4. Wähle das Gerät aus und klicke **"Add Selected"**

#### Option B: Manuell hinzufügen

1. Klicke auf das **+ Symbol** in der Toolbar
2. Fülle folgende Felder aus:
   - **Name:** Ein Name für deinen TV (z.B. "Wohnzimmer TV")
   - **IP-Adresse:** Die IP deines TVs (z.B. 192.168.1.100)
   - **MAC-Adresse:** Im Format AA:BB:CC:DD:EE:FF
3. Klicke **"Add Device"**

### Schritt 2: Gerät koppeln

1. Wähle dein Gerät in der Seitenleiste aus
2. Klicke auf **"Pair Device"**
3. **Auf dem TV erscheint eine Pairing-Anfrage** - bestätige diese!
4. Status sollte jetzt "Paired" sein ✓

### Schritt 3: Testen

1. Klicke **"Test Power On"** - dein TV sollte sich einschalten
2. Klicke **"Test Power Off"** - dein TV sollte sich ausschalten

### Schritt 4: Automatisierung aktivieren

1. Aktiviere **"Automatically manage this device"**
2. Klicke **"Save"**
3. Fertig! 🎉

## Funktionen

### Automatische Steuerung

Wenn "Automatically manage" aktiviert ist, reagiert dein TV auf:

| Mac Event | TV Reaktion |
|-----------|-------------|
| Mac schläft ein | TV schaltet sich aus |
| Mac wacht auf | TV schaltet sich ein |
| Mac fährt herunter | TV schaltet sich aus |
| Mac startet neu | TV schaltet sich aus |
| Display schläft ein | TV schaltet sich aus |
| Display wacht auf | TV schaltet sich ein |

### User Idle Mode

Zusätzlicher Schutz vor Burn-in:

1. Öffne **Einstellungen** (⚙️ Symbol)
2. Gehe zum Tab **"Automation"**
3. Aktiviere **"Enable User Idle Mode"**
4. Stelle die Idle-Zeit ein (Standard: 5 Minuten)

Der TV schaltet sich automatisch aus, wenn du den Mac nicht benutzt, und wieder ein, wenn du zurückkehrst.

### Wake-on-LAN Methoden

Falls dein TV nicht eingeschaltet werden kann:

1. Wähle dein Gerät aus
2. Unter "Wake-on-LAN Method" probiere:
   - **Broadcast** (Standard, am kompatibelsten)
   - **Target IP Address** (bei manchen Netzwerken besser)
   - **Subnet Directed Broadcast** (für spezielle Setups)

## Fehlerbehebung

### TV schaltet sich nicht ein

**Problem:** Wake-on-LAN funktioniert nicht

**Lösungen:**
1. ✅ Stelle sicher, dass "TV einschalten über WiFi" in den TV-Einstellungen aktiviert ist
2. ✅ Verwende eine statische IP-Adresse für den TV
3. ✅ Bei WiFi-Verbindung: Aktiviere "Always Ready" (2022+ Modelle) oder "Quickstart+" (ältere Modelle)
4. ✅ Teste verschiedene Wake-on-LAN Methoden
5. ✅ Stelle sicher, dass Mac und TV im gleichen Netzwerk/Subnetz sind
6. ✅ Schalte den TV einmal manuell ein, falls die Netzwerkverbindung unterbrochen war

### TV schaltet sich nicht aus

**Problem:** Power-Off Befehl funktioniert nicht

**Lösungen:**
1. ✅ Überprüfe, ob das Gerät "Paired" ist
2. ✅ Teste die Verbindung mit dem Test-Button
3. ✅ Stelle sicher, dass die IP-Adresse korrekt ist
4. ✅ Versuche, das Gerät erneut zu koppeln (Remove → neu hinzufügen)

### TV wird nicht gefunden beim Scannen

**Lösungen:**
1. ✅ Stelle sicher, dass der TV eingeschaltet ist
2. ✅ Mac und TV müssen im gleichen Netzwerk sein
3. ✅ Erlaube "Local Network" Zugriff in macOS Systemeinstellungen → Datenschutz
4. ✅ Prüfe Firewall-Einstellungen
5. ✅ Füge das Gerät manuell hinzu

### Automatische Steuerung funktioniert nicht

**Lösungen:**
1. ✅ Stelle sicher, dass "Automatically manage this device" aktiviert ist
2. ✅ Das Gerät muss "Enabled" sein
3. ✅ Überprüfe die Logs: `/tmp/com.lgtvcompanion.daemon.log`
4. ✅ Starte die App neu

## Erweiterte Einstellungen

### Launch at Login

Um die App beim Login automatisch zu starten:

1. Öffne Einstellungen → General
2. Aktiviere **"Launch at login"**

### Logs einsehen

Für Debugging-Zwecke:

```bash
# Daemon Logs
tail -f /tmp/com.lgtvcompanion.daemon.log

# Error Logs
tail -f /tmp/com.lgtvcompanion.daemon.error.log
```

## Tipps & Tricks

### 💡 Optimale TV-Einstellungen

Für beste Ergebnisse:

1. **Deaktiviere** die automatische Abschaltung des TVs:
   - Einstellungen → OLED Care → Automatische Abschaltung → 8 Stunden (oder mehr)
   - So vermeidest du Konflikte mit der App-Steuerung

2. **Aktiviere Quickstart+/Always Ready:**
   - Für schnelleres Einschalten über Netzwerk
   - Bei WiFi-Verbindung besonders wichtig

3. **Verwende ein Ethernet-Kabel:**
   - Zuverlässiger als WiFi für Wake-on-LAN
   - Schnellere Reaktionszeiten

### 💡 Multiple TVs

Du kannst mehrere TVs gleichzeitig verwalten:

1. Füge jeden TV wie beschrieben hinzu
2. Konfiguriere jeden einzeln
3. Alle werden gleichzeitig gesteuert

### 💡 Energy Saver Konflikt

Falls macOS Energy Saver mit der App kollidiert:

- Systemeinstellungen → Energie → Displays ausschalten nach → Nie
- Oder passe die User Idle Zeit entsprechend an

## Unterstützung

- **GitHub Issues:** [Link zum Repository]
- **Diskussionen:** [Link zu Discussions]
- **Original Windows App:** https://github.com/JPersson77/LGTVCompanion

## Bekannte Einschränkungen

- ⚠️ TV und Mac müssen im gleichen Subnetz/VLAN sein
- ⚠️ Pixel Refresh beim TV kann Wake-on-LAN blockieren (warte auf das Klick-Geräusch)
- ⚠️ Manuelles Ausschalten mit der Fernbedienung kann Auto-Reconnect verhindern
