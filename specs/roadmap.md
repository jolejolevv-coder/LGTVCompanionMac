# Roadmap LGTV Companion

## Status 28.10.2026
- Erledigt: 1.0 bis 1.2.0 (Pairing, Software Volume, Edifier Steuerung, EQ,
  Nachtmodus, Stromsparen Schalter), Nachtmodus Fix auf `main`.
- Freigegeben 28.10.2026, je Phase eine eigene Sitzung: BAMA Verbesserungen,
  `specs/features/bama-review-improvements.md`
  - Phase 1 Stabilität: fertig 28.10.2026 (merge 0de3cb7, 104 Tests)
  - Phase 2 Testbarkeit und Werkzeug: fertig 28.10.2026 (124 Tests, --install)
  - Phase 3 Bedienung nach Apple Regeln: fertig 28.10.2026 (132 Tests), Klicktest offen
  - Phase 4 Tastatur und VoiceOver: fertig 28.10.2026, Klicktest offen
  - Phase 5 Swift 6
- Danach optional Release 1.3.0.

## Retrospektive Phase 1 (BAMA)
1. Gut: Reviews gegen ein festes Regelwerk lieferten konkrete Fundstellen,
   der Fake Transport macht die Verbindungsrennen ohne TV testbar.
2. Falsche Annahmen: keine größeren; die Reviews hatten zum Teil Zeilen
   ungenau, deshalb vor dem Plan selbst nachgeprüft.
3. Besser spezifizieren: der Pairing Knopf in DeviceDetailView umgeht noch
   TVSession, das gehört in Phase 3 (Bedienung).

## Retrospektive Phase 2 (BAMA)
1. Gut: Tastenweg ist jetzt eine reine Funktion mit Tabellentest, das Build
   Skript prüft Signatur und Plist und installiert selbst.
2. Falsche Annahmen: der Builder hielt einen toten Parameter für gewünscht,
   die Projektregel "nie installieren" widersprach dem bisherigen Ablauf; beides
   korrigiert.
3. Besser spezifizieren: im Brief sagen, welche Testfälle Pflicht sind, statt
   Beispiele zu nennen, die als Signaturvorgabe gelesen werden.

## Retrospektive Phase 3 (BAMA)
1. Gut: Settings, Menüs, Reset und Permissions in einem Durchgang, Reset per
   Test gegen eine eigene Defaults Suite belegt.
2. Falsche Annahmen: SwiftUI öffnet ein `Window` beim Start immer; der Builder
   versteckt es per Alpha, dazu kam `LSUIElement`, damit nichts im Dock springt.
3. Besser spezifizieren: UI Phasen brauchen eine Klickliste für den Nutzer
   schon in der Spec, weil der Agent die App nicht bedienen soll.

## Retrospektive Phase 4 (BAMA)
1. Gut: Identifier zentral in `App/AccessibilityID.swift`, Commits entprellt.
2. Falsche Annahmen: "Display mode capsules" war im Brief unklar, der Builder
   hat die HDMI Kapseln und das Auflösungsmenü genommen.
3. Besser spezifizieren: Controls im Brief mit Datei und Namen nennen.
