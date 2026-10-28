## Goal
Die App nach den Regeln des BAMA Skill Sets (github.com/daveebbelaar/bama)
stabiler, mac typischer und für einen Agent prüfbarer machen, ohne die
erprobten Verbindungsdetails (wss URL Form, TLS 1.2) anzufassen.

## Background
Am 28.10.2026 haben drei Reviews die App gegen BAMA geprüft: Design und UX
(mac-design, ux-design, app-icon), Code (swift-swiftui, os-integrations,
performance, improve-architecture) und Auslieferung (test-mac-app,
build-and-verify, improve-loop). Stand vorher: 93 Tests grün, Build im Swift 5
Modus ohne Warnungen, mit `-strict-concurrency=complete` 205 Warnungen.

Selbst im Code nachgeprüft: `isPaired` wird beim Abbruch der Verbindung nicht
zurückgesetzt (`Shared/WebOSClient.swift:235-246`), `withConnectedClient`
erlaubt zwei gleichzeitige connect und register auf demselben Client
(`Shared/DeviceManager.swift:268-294`), Power Monitoring startet nur aus
`onAppear` einer View, der About Tab sucht ein `AppIcon.png`, das der Build
nicht kopiert.

## Scope
- In scope: Fehler und Risiken aus dem Code Review, sichtbare Fehler statt
  stiller `try?`, Settings und Menüs nach Apple Konvention, Tastatur und
  VoiceOver für die eigenen Controls, reine Logik aus `DeviceManager`
  herausziehen und testen, Prüfschritt im Build Skript, `CLAUDE.md` fürs
  Projekt.
- Out of scope: Änderungen am Verbindungsaufbau zum TV (URL Form, TLS),
  Liquid Glass Icon (macOS 26), Notarisierung, Sparkle, neue Funktionen.
- Phase 5: Umstieg auf Swift 6 (am 28.10.2026 gewählt). Debug Bridge mit
  Snapshots und Selftest bleibt draußen.

## Acceptance criteria
Tag in Klammern: wie das Kriterium belegt wird.

Phase 1, Stabilität
- [ ] Gleichzeitige Befehle an einen TV teilen sich einen laufenden connect
      und register, kein Aufruf hängt mehr (unit, mit Fake Transport).
- [ ] Nach einem Verbindungsabbruch wird `isPaired` zurückgesetzt, der erste
      Befehl danach braucht keinen Umweg über den Fehlerpfad (unit).
- [ ] Wiederholt wird nur bei `notConnected`, `timeout`, `networkError`,
      nicht bei Abbruch oder abgelehntem Befehl (unit).
- [ ] Sleep und Wake Automatik startet in `applicationDidFinishLaunching`,
      auch ohne offenes Fenster (Code, manuell nach Neustart).
- [ ] `@Published` Zustand wird nur auf dem Main Actor gelesen und
      geschrieben (Code Review, Warnungszahl strict concurrency sinkt).
- [ ] Lautstärketaste: keine Core Audio Abfrage und kein Speichern pro
      Tastendruck auf dem Main Thread im Tap Callback (Code, manuell hören).
- [ ] Event Tap wird in `stop()` invalidiert (Code).
- [ ] Kein `fatalError` mehr in der UI (`ContentView.binding(for:)`).
- [ ] Launch at login zeigt Fehler, setzt den Schalter zurück und behandelt
      `requiresApproval`; ein Start als Login Item holt kein Fenster nach vorn
      (manuell).
- [ ] Timer haben eine Toleranz, Keychain wird nur bei geändertem Schlüssel
      geschrieben, der Scan prüft jede IP nur einmal (Code, unit für Dedupe).

Phase 2, Testbarkeit und Werkzeug
- [ ] Tastenweg (Speaker, Software Volume, TV, macOS) ist eine reine
      Funktion `VolumeKeyRoute` mit Tabellentest (unit).
- [ ] Tests für Wake on LAN Paket, SSDP Parsing und Request JSON (unit).
- [ ] Fehler gehen über `os.Logger` statt `print`, der Manager führt
      `lastError` (Code).
- [ ] `scripts/build-release.sh` prüft Signatur (Leaf Zertifikat statt ad
      hoc), Info.plist und Usage Strings; bricht lokal ab statt still ad hoc
      zu signieren; `--install` ersetzt die App in /Applications und startet
      sie neu (Skript Lauf).
- [ ] `CLAUDE.md` im Projekt: Aufbau, Befehle, was nur von Hand prüfbar ist,
      Regel "nie gegen echte TVs, Defaults oder Keychain testen" (Datei).

Phase 3, Bedienung nach Apple Regeln
- [ ] Settings nur noch als Settings Fenster (⌘,), Sheet und Zahnrad im
      Hauptfenster entfallen; Menüpanel bekommt einen Eintrag "Settings…".
- [ ] Menüleiste hat Menüs "TV" und "Speakers" mit Kurzbefehlen für Scan,
      Add TV, Refresh, Screen On/Off, Power On/Off, Night Mode.
- [ ] Erfolg erscheint inline als Statuszeile, Alerts nur noch für Fehler mit
      Handlung, Titel nennt den Vorgang ("Unable to Pair").
- [ ] Fehlgeschlagene Aktionen im Menüpanel zeigen eine Zeile mit Ursache und
      Abhilfe statt still zu scheitern.
- [ ] Geräteeinstellungen speichern sofort, ohne Save Knopf; IP und MAC
      werden erst gespeichert, wenn sie gültig sind.
- [ ] Settings bekommt einen Bereich Permissions: Accessibility, System Audio,
      Bluetooth jeweils mit Zustand und Knopf zur Systemeinstellung, Zustand
      wird alle 2 s geprüft, solange etwas fehlt.
- [ ] Hilfetexte stehen im Footer und sind kurz, Toggles einheitlich ohne
      grüne Sonderfarbe, Labels als Aussagen.
- [ ] "Reset All Settings" setzt wirklich alles zurück (auch Speaker, Night
      Mode, Media Keys) oder heißt "Remove All TVs"; destruktive Knöpfe mit
      `role: .destructive`, Return löst nichts Destruktives aus.
- [ ] Einheitlich "TV" statt "Device" in Titeln; "Wake" heißt "Power On";
      Quit hat nicht dasselbe Symbol wie Power Off.
- [ ] Keine Schrift unter 10 pt, Auswahlkapseln mit Systemfarben statt fest
      Schwarz und Weiß, lesbar in Hell und Dunkel.
- [ ] About zeigt das echte App Icon (`NSApp.applicationIconImage`).
- [ ] Kein Dock Icon im Normalbetrieb; es erscheint nur, solange das
      Hauptfenster offen ist. Beim Start öffnet sich kein Fenster.

Phase 4, Tastatur und VoiceOver
- [ ] Lautstärke Slider ist per Tab erreichbar und mit Pfeiltasten bedienbar;
      VoiceOver Schritte schicken entprellt einen Befehl statt einen je Schritt.
- [ ] Kapselgruppen (Input, Sound, Subwoofer) haben ein Gruppenlabel und
      mindestens 24 pt Höhe.
- [ ] Volume HUD wird VoiceOver angesagt und hat bei "Transparenz reduzieren"
      einen festen Hintergrund.
- [ ] Wichtige Controls tragen `accessibilityIdentifier`, damit ein Agent den
      Zustand über den Accessibility Baum lesen kann.

Für jede Phase: Tests grün, CI grün, App gebaut und installiert, Ton und Tasten
von dir abgenommen, wo das nötig ist.

## Implementation plan
Phase 1: Stabilität. Pro Client ein einziger laufender Verbindungsaufbau
  (`ClientSession` als actor oder ein gemeinsamer Task), dahinter ein Protokoll
  `TVTransport`, damit der Fake Transport die Rennen testbar macht. Danach die
  kleineren Punkte aus der Liste, je ein Commit.
Phase 2: Testbarkeit und Werkzeug. `VolumeKeyRoute` aus `handleMediaKey`
  ziehen, Protokolltests, Logger, Build Skript Prüfschritt, `CLAUDE.md`,
  `TODO.md` auf den echten Stand bringen.
Phase 3: Bedienung. Settings Scene, Command Menüs, Statuszeilen statt Alerts,
  Permissions Bereich, Texte, Reset, Benennung.
Phase 4: Tastatur und VoiceOver für die eigenen Controls.
Phase 5: Umstieg auf Swift 6. Erst `StrictConcurrency` als Upcoming Feature,
  Warnungen abbauen, Closures für Hintergrundqueues als `@Sendable` markieren,
  dann tools version 6.0. Abnahme: 0 Warnungen, App läuft eine Nacht mit
  Sleep und Wake ohne Absturz.

Danach Release 1.3.0, wenn du das willst.

## Design decisions
- Transport Protokoll statt direkter Tests gegen `WebOSClient`: kostet eine
  Abstraktion, dafür werden die Rennen beim Verbinden und das Retry Verhalten
  ohne TV testbar. Ein lokaler Fake WebSocket Server wäre echter, aber deutlich
  teurer.
- Swift 6 nicht in Phase 1: 205 Warnungen sind ein eigener Block mit Risiko
  für Laufzeitfehler auf Hintergrundqueues. Phase 1 behebt die echten Rennen
  gezielt, der Sprachmodus folgt optional.
- BAMA zielt auf macOS 26. Liquid Glass Regeln bleiben außen vor, die App
  bleibt bei macOS 14.2 als Minimum.

## Decisions (28.10.2026)
- Dock: nur Menüleiste, Dock Icon nur solange das Hauptfenster offen ist.
- Geräteeinstellungen: sofort speichern, kein Save Knopf.
- Phase 5: Swift 6 ja, Debug Bridge nein.

## Open questions
- Keine. Plan am 28.10.2026 vom Nutzer freigegeben.
