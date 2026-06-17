## Goal
Den TV nicht automatisch ausschalten, solange er einen anderen Eingang zeigt
als den Mac (z. B. eine PS5 auf einem anderen HDMI-Port).

## Scope
- In scope: Auslesen des aktuellen TV-Vordergrund-Eingangs; pro Gerät einen
  „Mac-Eingang" speichern; alle automatischen Aus-Pfade gegen diesen Eingang
  absichern; Auto-Erkennung per Knopf in der Geräte-Detailansicht.
- Out of scope: Eingang automatisch auf den Mac umschalten; manuelles
  Ausschalten (Menü) — das bleibt absichtlich ungefiltert.

## Acceptance criteria
- [x] `WebOSClient.getForegroundAppInfo()` liefert die aktive App-/Eingang-ID.
- [x] `WebOSDevice.macInputAppId` (optional, rückwärtskompatibel decodiert).
- [x] Vor automatischem Aus prüft die App den Eingang; bei abweichendem,
      nicht-leerem Eingang wird das Gerät übersprungen.
- [x] Gilt für Idle, System-Sleep, Display-Sleep, Shutdown/Restart und
      App-Shutdown (`powerOffAll` + `powerOffManagedDevices`).
- [x] „Detect / Re-detect / Clear" pro Gerät; ID wird lesbar angezeigt
      (`com.webos.app.hdmi3` → „HDMI 3").

## Implementation plan
Phase 1: `WebOSClient.swift` — `getForegroundAppInfo()`; Modellfeld
         `macInputAppId` inkl. CodingKeys/Decoder.
Phase 2: `DeviceManager.swift` — `tvShowsMacInput` / `devicesShowingMacInput`,
         Einhängen in `powerOffAll` & `powerOffManagedDevices`;
         `readForegroundInput(for:)` für die UI.
Phase 3: `DeviceDetailView.swift` — „Mac input" mit Detect-Knopf + Formatter.

## Design decisions
- Mac-Eingang per Knopf erkennen (ein Klick, während der TV den Mac zeigt)
  statt manuellem Dropdown.
- Geltung: alle Auto-Aus-Auslöser (nicht nur Idle), für konsistentes Verhalten.
- Fail-safe: Kann der Eingang nicht gelesen werden, wird **trotzdem**
  ausgeschaltet — eine flackernde Abfrage darf das Kern-Feature nicht blockieren.
- Opt-in pro Gerät: ohne gesetzten `macInputAppId` Verhalten wie zuvor.

## Open questions
- Beim Sleep kostet die Prüfung eine Netz-Abfrage im 20-s-Fenster; bisher
  unkritisch dank Keepalive. Falls Sleep mal zu langsam wird, hier zuerst prüfen.
