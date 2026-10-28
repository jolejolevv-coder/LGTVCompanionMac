# Roadmap LGTV Companion

## Status 28.10.2026
- Erledigt: 1.0 bis 1.2.0 (Pairing, Software Volume, Edifier Steuerung, EQ,
  Nachtmodus, Stromsparen Schalter), Nachtmodus Fix auf `main`.
- Freigegeben 28.10.2026, je Phase eine eigene Sitzung: BAMA Verbesserungen,
  `specs/features/bama-review-improvements.md`
  - Phase 1 Stabilität: fertig 28.10.2026 (merge 0de3cb7, 104 Tests)
  - Phase 2 Testbarkeit und Werkzeug
  - Phase 3 Bedienung nach Apple Regeln
  - Phase 4 Tastatur und VoiceOver
  - Phase 5 Swift 6
- Danach optional Release 1.3.0.

## Retrospektive Phase 1 (BAMA)
1. Gut: Reviews gegen ein festes Regelwerk lieferten konkrete Fundstellen,
   der Fake Transport macht die Verbindungsrennen ohne TV testbar.
2. Falsche Annahmen: keine größeren; die Reviews hatten zum Teil Zeilen
   ungenau, deshalb vor dem Plan selbst nachgeprüft.
3. Besser spezifizieren: der Pairing Knopf in DeviceDetailView umgeht noch
   TVSession, das gehört in Phase 3 (Bedienung).
