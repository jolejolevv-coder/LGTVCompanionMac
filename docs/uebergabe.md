# Übergabe LGTV Companion

## Stand 28.10.2026
Version 1.2.0 ist released, auf `main` liegt zusätzlich der Nachtmodus Fix
(be83a43, nicht released). 93 Tests grün, CI grün, App installiert in
/Applications. Am 28.10. wurde die App mit drei Reviews gegen das BAMA Skill
Set (github.com/daveebbelaar/bama, Klon nur im Scratchpad, nicht installiert)
geprüft. Ergebnis und Plan stehen in `specs/features/bama-review-improvements.md`
(fünf Phasen mit Akzeptanzkriterien). Code ist dafür noch nicht geändert.

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
   Jetzt Phase 3, danach 4 und 5 laut Spec, alles in dieser Sitzung (Nutzer:
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
