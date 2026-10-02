## Goal
Die MAC Adresse des TV selbst ermitteln, damit sie beim Hinzufügen nicht mehr
aus den Netzwerkeinstellungen des TV abgetippt werden muss.

## Scope
- In scope: MAC direkt beim TV erfragen (SSDP, Dienst DIAL, Header `WAKEUP`);
  im Scanner automatisch vorbelegen; im Dialog "Add Device" per Knopf "Detect";
  Eingabe von Hand bleibt möglich und hat Vorrang.
- Out of scope: Geräte, die keine DIAL Suche beantworten; die MAC der jeweils
  anderen Schnittstelle des TV automatisch wählen; IPv6.

## Acceptance criteria
- [x] Der Header `WAKEUP: MAC=…;Timeout=…` wird geparst, unabhängig von
      Schreibweise und Reihenfolge der Felder (Tests mit echter Antwort).
- [x] Ergebnis in der Form `80:5B:65:D6:27:E0`, Platzhalteradressen und
      Antworten ohne Header liefern nichts (Tests).
- [x] Gegen den echten TV: 192.168.178.25 ergibt 80:5B:65:D6:27:E0 in 0,1 s,
      eine tote Adresse nach 2 s nichts (Testprogramm, 02.10.2026).
- [x] Der Scanner belegt das MAC Feld vor, eine Eingabe von Hand überschreibt.
- [x] "Add Device" hat einen Knopf "Detect", aktiv bei gültiger IP.
- [x] Antwortet kein TV, erscheint ein Hinweis statt eines stillen Fehlers.
- [x] In der installierten App bestätigt: Detect im Dialog liefert
      80:5B:65:D6:27:E0 (Nutzer, 02.10.2026). Scanner nutzt denselben Weg.

## Implementation plan
Phase 1: `Shared/MACAddressResolver.swift` mit `parse`, `normalize` und
         `resolve` (eine SSDP Anfrage direkt an die IP), dazu Tests.
Phase 2: `DeviceDiscovery.considerDevice` fragt nach dem Porttest die MAC ab.
Phase 3: `DeviceScannerView` und `AddDeviceView`.

## Design decisions
- Den TV fragen statt die ARP Tabelle des Mac lesen. Der erste Entwurf nutzte
  `arp -n`. Das scheitert: macOS zeigt Apps keine ARP Einträge (Schutz Lokales
  Netzwerk), auch nicht bei erteilter Freigabe. In der App kam für jeden Host
  "no entry". Der TV nennt die Adresse dagegen selbst, und zwar genau die, die
  er für Wake on LAN vorsieht.
- Unicast SSDP an die IP statt Multicast. So funktioniert "Detect" auch für
  eine von Hand eingetragene IP, ohne vorherigen Scan.
- Einfacher UDP Socket statt `NWConnection`. Der TV antwortet von einem
  anderen Port als 1900, ein verbundener Socket würde die Antwort verwerfen.
- Zwei Versuche mit je 1 s Wartezeit, weil UDP Pakete verloren gehen können.

## Known limits
- Der Header nennt die MAC der Verbindung, über die der TV gerade im Netz
  hängt. Am 02.10.2026 war das WLAN (`80:5B:65:D6:27:E0`). Die Buchse für das
  Kabel hat eine eigene MAC (`7C:64:6C:66:5F:67`, steht in der
  Gerätebeschreibung des TV unter `wiredMac`). Wechselt der TV die Verbindung,
  muss die MAC im Gerät angepasst werden. Der Scanner weist darauf hin.
- Gilt für LG webOS. Andere Hersteller senden den Header nicht zwingend.

## Open questions
- Keine.
