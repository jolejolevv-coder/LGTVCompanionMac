## Goal
Die App schaltet den TV nur dann automatisch aus, wenn der Mac gerade wirklich
auf dem TV ausgibt, damit eine PS5 am TV nicht nach ein paar Minuten schwarz
wird.

## Background
Gemeldet am 04.11.2026: Der Nutzer zieht das HDMI Kabel vom Mac ab und spielt
an der PS5. Nach einigen Minuten wird der TV Bildschirm schwarz.

Befund am Gerät: `userIdleEnabled = 1`, `userIdleTimeout = 300` (5 Minuten),
`useScreenOff = true`, `macInputAppId = com.webos.app.hdmi2`. Der Mac zeigt
gerade auf einem Lenovo T24i, nicht auf dem TV. Ablauf: Der Mac wird nicht
bedient, nach 5 Minuten meldet der Idle Monitor "idle", `powerOffAll` schickt
Screen Off. Die einzige Bremse ist die Prüfung des Eingangs
(`tvShowsMacInput`). Sie greift nicht, wenn die PS5 am selben HDMI Port hängt
wie vorher der Mac (Kabel umgesteckt). Sie greift auch nicht, wenn der
Eingang nicht lesbar ist, weil sie dann absichtlich trotzdem ausschaltet.

## Scope
- In scope: Vor jedem automatischen Aus (Idle, Display Sleep, System Sleep,
  Shutdown, Restart, App Ende, Display Wechsel) prüfen, ob der Mac gerade
  einen LG TV als Display ansteuert. Wenn nicht, wird nichts ausgeschaltet.
  Die Prüfung des Eingangs bleibt zusätzlich bestehen.
- Out of scope: Einschalten (Wake, Ende von Idle) bleibt unverändert, weil ein
  ausgeschalteter TV dem Mac oft gar nicht mehr als Display erscheint.
  Manuelles Aus aus dem Menü bleibt ungefiltert.

## Acceptance criteria
- [x] Reine Funktion entscheidet "darf automatisch aus" aus: Mac steuert LG
      TV an (ja oder nein), Eingang laut TV (Mac, anderer, unbekannt, nicht
      konfiguriert). Tabellentest (unit).
- [x] Mac ohne LG TV Display: Idle nach 5 Minuten schaltet nichts aus (unit
      für die Entscheidung und den Filter `devicesAllowedToAutoOff`; an der
      PS5 prüft der Nutzer).
- [ ] Mac zeigt auf dem TV und wird nicht bedient: TV geht wie bisher nach
      5 Minuten aus (manuell, prüft der Nutzer).
- [x] Erkennung des LG TV über die Displays des Mac (Hersteller LG im EDID
      oder Name mit "LG TV"), Ergebnis wird geloggt (`Log.tv`).
- [x] Der Pfad "kein Display mehr angeschlossen, TV aus" schaltet nicht mehr
      aus, weil der Mac dann kein LG TV ansteuert (Code).
- [ ] 138 Tests plus neue grün, CI grün, installiert.

## Implementation plan
Phase 1: `Shared/AutoOffPolicy.swift` mit der reinen Entscheidung plus Test.
  `Shared/DisplayControl.swift` (oder neuer kleiner Helfer) liefert "Mac
  steuert ein LG TV an" über `CGGetActiveDisplayList` und
  `CGDisplayVendorNumber` (LG = 0x1E6D) mit Fallback auf den Displaynamen.
  `DeviceManager.powerOffAll` und `powerOffManagedDevices` nutzen beides.
  Spec, `ARCHITECTURE.md`, Übergabe nachziehen, installieren.

## Design decisions
- Kriterium ist das Display am Mac, nicht ein neuer Schalter. Es trifft den
  Fall genau (Kabel ab heißt: TV gehört gerade jemand anderem) und braucht
  keine Bedienung. Preis: Hängt einmal ein zweiter LG Bildschirm am Mac, hält
  die App den für den TV. Bei einem TV am Mac mini unkritisch.
- Bisher galt "im Zweifel ausschalten". Neu gilt "ohne Mac auf dem TV nie
  ausschalten". Preis: Wer das Kabel abzieht und weggeht, dem lässt die App
  den TV an. Der TV schaltet sich bei fehlendem Signal nach einer Weile selbst
  ab.

- Umsetzung nutzt `CGGetOnlineDisplayList` statt `CGGetActiveDisplayList`:
  Online zählt auch ein Display, das gerade einschläft (Display Sleep Pfad).
  Ein gezogenes Kabel nimmt das Display trotzdem aus der Liste.

## Open questions
- Keine. Freigegeben am 04.11.2026 ("passt").
