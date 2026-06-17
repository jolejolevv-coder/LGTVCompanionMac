## Goal
Den TV nicht in den Idle-Aus schicken, während eine erlaubte App tatsächlich
ein Video abspielt (z. B. YouTube im Browser), obwohl Maus und Tastatur ruhen.

## Scope
- In scope: Erkennung aktiver Display-Sleep-Assertions pro App; Erlaubnisliste
  (allowlist) pro Bundle-ID; UI zum Freischalten in den Automation-Settings.
- Out of scope: Site-spezifische Erkennung (nur YouTube vs. andere Videoseiten
  im selben Browser) — bewusst verworfen, siehe Tradeoffs.

## Acceptance criteria
- [x] App liest über `IOPMCopyAssertionsByProcess` alle Prozesse mit aktiver
      Display-Sleep-Assertion (`PreventUserIdleDisplaySleep` /
      `NoDisplaySleepAssertion`, Level „on").
- [x] `UserIdleMonitor` meldet nicht „idle", solange eine App aus der
      Erlaubnisliste eine aktive Assertion hält.
- [x] Erlaubnisliste wird per Bundle-ID + Name in UserDefaults persistiert.
- [x] Settings zeigen Live-Liste (gerade aktiv) ∪ gemerkte Einträge, je mit
      Toggle; aktualisiert sich alle 3 s, solange das Fenster offen ist.

## Implementation plan
Phase 1: `Shared/DisplaySleepAssertions.swift` — Assertions auslesen, PID →
         Bundle-ID/Name auflösen (`AssertingApp`).
Phase 2: `PowerEventMonitor.swift` — `allowedAssertionBundleIDs` im
         `UserIdleMonitor`; Override in `checkIdleState()`.
Phase 3: `DeviceManager.swift` — `assertionAllowlist`, Persistenz, Verdrahtung.
Phase 4: `SettingsView.swift` — Abschnitt „Keep TV On During Playback".

## Design decisions
- Default: Erlaubnisliste (TV geht standardmäßig aus, nur ausgewählte Apps
  halten ihn an). Gewählt vom Nutzer gegenüber der Blockliste.
- Granularität: per-App. Die Assertion wird nur *während* Playback gehalten,
  „Safari nur wenn Video läuft" ist damit gratis. Site-spezifisch (nur YouTube)
  wurde verworfen: bräuchte AppleScript/Automation pro Browser, übersieht
  Hintergrund-Tabs, fragil.

## Open questions
- Reine Audio-Wiedergabe hält i. d. R. keine Display-Sleep-Assertion → TV geht
  dann weiterhin aus. Falls gewünscht, separat behandeln.
