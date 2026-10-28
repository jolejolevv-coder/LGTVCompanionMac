# Übergabe LGTV Companion

## Stand 28.10.2026
Version 1.2.0 ist released, auf `main` liegt zusätzlich der Nachtmodus Fix
(be83a43, nicht released). 93 Tests grün, CI grün, App installiert in
/Applications. Am 28.10. wurde die App mit drei Reviews gegen das BAMA Skill
Set (github.com/daveebbelaar/bama, Klon nur im Scratchpad, nicht installiert)
geprüft. Ergebnis und Plan stehen in `specs/features/bama-review-improvements.md`
(fünf Phasen mit Akzeptanzkriterien). Code ist dafür noch nicht geändert.

## Phase 5 Checkpoint (Branch bama-phase-5, 28.10.2026)
Fertig auf dem Branch, nicht gemerged, nicht installiert: Swift 6 Sprachmodus
(`swift-tools-version: 6.0`), 0 Warnungen im Build und in den Tests, 138 Tests
grün, `./scripts/build-release.sh` ohne `--install` gelaufen. Isolation:
UI nahe Typen und alle Monitore sind `@MainActor`, `WebOSClient` bleibt auf
seiner Queue (`@unchecked Sendable`), `TVSession` bleibt Actor. Callbacks von
fremden Queues gehen über `MainThread` (`Shared/MainThread.swift`). Die volle
Liste je Callback steht in `ARCHITECTURE.md`, Abschnitt "Threads und Concurrency".
CI läuft jetzt auf macos-15 mit Xcode 16.4, weil `isolated deinit` Swift 6.1
braucht. Die TV Verbindung (URL Form, TLS 1.2, Handshake) ist unverändert.
Annahmen: DeviceManager Methoden laufen jetzt auf dem Main Actor, die
Mindest TLS Version nutzt denselben Wert 0x0301 wie vorher, nur ohne die
veraltete Konstante.
Vom Nutzer zu prüfen: über Nacht Sleep und Wake mit dem TV, Lautstärketasten
(Software Volume und Speaker), HUD, Bluetooth Verbindung zu den Edifiers,
Zugriff auf Bedienungshilfen nach dem Start. Nicht automatisch getestet:
Event Tap der Medientasten, CoreBluetooth, WebOSClient Verbindung, Audio Tap.

## Entscheidungen des Nutzers
- Dock: nur Menüleiste, Dock Icon nur solange das Hauptfenster offen ist,
  beim Start kein Fenster. Grund: typisches Verhalten einer Menüleisten App.
- Geräteeinstellungen speichern sofort, kein Save Knopf (Apple Konvention).
- Phase 5 nur Swift 6 Umstieg, keine Debug Bridge.

## Nächste Schritte
1. Plan ist freigegeben (28.10.2026). Nutzer will jede Phase in einer eigenen
   Sitzung, um Tokens zu sparen.
2. Erledigt 28.10.: Phase 1 Stabilität (merge 0de3cb7, installiert). Inhalt: `TVTransport` Protokoll plus ein laufender
   connect und register pro Client (`Shared/DeviceManager.swift:268-294`,
   `Shared/WebOSClient.swift`), `isPaired = false` in den `.failed` und
   `.cancelled` Zweigen (`WebOSClient.swift:235-246`), Retry nur bei
   transienten Fehlern, `startPowerEventMonitoring` in
   `applicationDidFinishLaunching`, übrige Punkte der Liste je ein Commit.
3. Erledigt 28.10.: Phase 2 (merge auf main, per --install installiert).
   Erledigt 28.10.: Phase 3 (installiert, startet als UIElement ohne Fenster).
   Erledigt 28.10.: Phase 4 und Phase 5 (merge a1128a9, installiert, kein
   Absturz beim Start). BAMA Plan komplett. Danach: Klicktests und Nachttest
   durch den Nutzer, Release 1.3.0 nur auf Wunsch. Alter Text: Phase 5 Swift 6 laut Spec, alles in dieser Sitzung (Nutzer:
   "mach dann hier"). Phase 3 zusätzlich: Pair Again in DeviceDetailView
   über DeviceManager und TVSession führen.
4. Von Hand offen nach Phase 1: Lautstärketasten, Sleep und Wake nach
   Neustart, Launch at login.

## Offene Fragen und bekannte Punkte
- Nutzer bestätigt noch, dass der Nachtmodus morgens um 8 Uhr ausgeht.
- Strict concurrency Build: 205 Warnungen, Log unter
  /private/tmp/claude-501/-Users-jole-Downloads/4aeaac15-c556-449e-b322-ad09f8dfea6e/scratchpad/sc.log
  (flüchtig). Neu erzeugen mit
  `swift build --scratch-path /tmp/lgtv-sc -Xswiftc -strict-concurrency=complete`.
- Keine `CLAUDE.md` und keine `specs/roadmap.md` im Projekt; `CLAUDE.md`
  entsteht in Phase 2.

## Startprompt für die nächste Sitzung
Ordner: /Users/jole/Downloads/LGTVCompanionMac

```
Lies CLAUDE.md (falls vorhanden), specs/roadmap.md und docs/uebergabe.md.
Setze Phase 1 aus specs/features/bama-review-improvements.md um, der Plan ist
freigegeben. Je Punkt ein Commit, Tests im selben Schritt, danach build,
install und CI prüfen. Wenn die Phase fertig ist: uebergabe Skill, dann die
nächste Phase in einer neuen Sitzung starten.
```

## Klickliste Phase 3 für den Nutzer
Panel "Open LGTV Companion" (Dock Icon erscheint, verschwindet beim Schließen),
"Settings…" und ⌘, kommen nach vorn, Menüs TV und Speakers mit Kurzbefehlen
(⌘N, ⇧⌘N, ⌘R, ⌥⌘1 bis 4, ⌥⌘N), Autosave von IP und MAC, Pair Again, rote
Fehlerzeile im Panel bei ausgeschaltetem TV, Permissions Zeilen, Return löst
Reset und Remove TV nicht aus, Hell und Dunkel lesbar, About zeigt das Icon.
Bekannt: Klick auf die App im Finder bei laufender App öffnet kein Fenster.

## Klickliste Phase 4
Tab auf den Lautstärkeslider im Panel, Pfeiltasten ändern ihn, ein Befehl
etwa 0,3 s nach dem Loslassen; Tab durch Input, Sound, Subwoofer Kapseln;
VoiceOver sagt "Volume N percent" beim Halten der Taste; mit "Transparenz
reduzieren" hat das HUD einen festen Hintergrund.

## CI nach Phase 5 (28.10.2026)
CI war rot: Xcode 16.4 hat Swift 6.1, `isolated deinit` braucht 6.2. Workflow
auf `macos-26` mit neuestem Xcode 26 umgestellt. Bleibt sie rot: Fehler mit
`gh run view <id> --log-failed | grep error:` lesen; Kandidat ist der Fehler
"non-sendable result type T" in `Shared/DeviceManager.swift` runOnConnectedClient
(Fix: `T: Sendable`). Phasen 3 und 4 waren in der CI schon rot (macos-15,
Swift 6.1 strenger als lokal 6.4), mit Phase 5 überholt.
