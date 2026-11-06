# Übergabe LGTV Companion

Stand: 06.11.2026

## Stand 04.11.2026: PS5 Fix (Auto Aus nur mit Mac am TV)
Gemeldet: Kabel vom Mac ab, PS5 läuft, nach 5 Minuten Idle schaltet die App
den Bildschirm aus. Fix nach `specs/features/auto-off-only-when-mac-on-tv.md`:
`Shared/AutoOffPolicy.swift` (reine Entscheidung), `Shared/LGDisplayDetector.swift`
(LG Hersteller 0x1E6D oder Name "LG TV" unter den Online Displays),
`DeviceManager.devicesAllowedToAutoOff` filtert jeden automatischen Aus Pfad.
144 Tests grün, 0 Warnungen, auf main, installiert (Version bleibt 1.3.0,
neue Buildnummer). Vom Nutzer zu prüfen: PS5 mit gezogenem Kabel länger als
5 Minuten bleibt an; Mac am TV ohne Bedienung geht nach 5 Minuten aus;
Mac schlafen legen mit Mac am TV schaltet weiter aus. Log dazu:
`log stream --predicate 'subsystem == "com.lgtvcompanion.mac" AND category == "tv"'`
zeigt "Auto off check".

## Stand 06.11.2026: Abgleich mit git
Fakten aus git: `main` steht auf 023753c, nichts ungepusht (origin/main gleich).
Tag v1.3.0 (28.10.2026, c332084) enthält BAMA Phasen 1 bis 5 inklusive Merge
a1128a9 von `bama-phase-5`. Die frühere Aussage "Phase 5 nicht gemerged, nicht
installiert" war überholt und steht im Archiv. Alle lokalen Branches sind in
`main` gemerged. CI ist grün auf macos-26 mit Xcode 26 (Swift 6.2). Aktuell 144
Tests, 0 Warnungen. `CLAUDE.md` und `specs/roadmap.md` existieren. Alte
Abschnitte (Stand 28.10., Phase 5 Checkpoint, CI nach Phase 5, alter Startprompt,
alte Nächste Schritte) liegen verbatim in `docs/uebergabe-archiv-2026-11-06.md`.
Falls CI wieder rot wird: `gh run view <id> --log-failed | grep error:`; Kandidat
ist "non-sendable result type T" in `Shared/DeviceManager.swift` runOnConnectedClient
(Fix: `T: Sendable`).

## Nächste Schritte
1. Klickliste Phase 3 und Phase 4 durch den Nutzer (siehe unten).
2. Nachttest Sleep und Wake mit Swift 6, Lautstärketasten, Launch at login.
3. Praxistest PS5 Fix (siehe Stand 04.11.2026).
4. Phase 3 Punkt Pair Again über DeviceManager und TVSession ist erledigt
   (Commit b6fcdd8).

## Annahmen
- Version 1.3.0 gilt als aktuell; der PS5 Fix trägt keine neue Versionsnummer.
- Phase 1 und 2 Handtests (Lautstärketasten, Launch at login) gelten als
  weiter offen, weil keine Bestätigung vorliegt.

## Entscheidungen des Nutzers
- Dock: nur Menüleiste, Dock Icon nur solange das Hauptfenster offen ist,
  beim Start kein Fenster. Grund: typisches Verhalten einer Menüleisten App.
- Geräteeinstellungen speichern sofort, kein Save Knopf (Apple Konvention).
- Phase 5 nur Swift 6 Umstieg, keine Debug Bridge.

## Offene Fragen und bekannte Punkte
- Nutzer bestätigt noch, dass der Nachtmodus morgens um 8 Uhr ausgeht.
- Strict concurrency Build: 205 Warnungen, Log unter
  /private/tmp/claude-501/-Users-jole-Downloads/4aeaac15-c556-449e-b322-ad09f8dfea6e/scratchpad/sc.log
  (flüchtig). Neu erzeugen mit
  `swift build --scratch-path /tmp/lgtv-sc -Xswiftc -strict-concurrency=complete`.
- Offene Frage: Soll nach dem Klicktest ein Release 1.3.1 mit dem PS5 Fix
  entstehen? Aktuell nur installiert, nicht getaggt.

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

