## Goal
Die MAC Adresse des TV selbst ermitteln, damit sie beim Hinzufügen nicht mehr
aus den Netzwerkeinstellungen des TV abgetippt werden muss.

## Scope
- In scope: MAC aus der ARP Tabelle des Mac lesen; im Scanner automatisch
  vorbelegen; im Dialog "Add Device" per Knopf "Detect"; Eingabe von Hand
  bleibt möglich und hat Vorrang.
- Out of scope: MAC über die webOS Schnittstelle abfragen (bräuchte Pairing vor
  dem Hinzufügen); MAC der jeweils anderen Schnittstelle des TV (LAN gegenüber
  WLAN); IPv6.

## Acceptance criteria
- [x] `arp -n` Ausgabe wird geparst, fehlende führende Nullen werden ergänzt,
      Ergebnis in der Form `80:5B:65:D6:27:E0` (Tests).
- [x] Einträge ohne Antwort (`incomplete`) und Platzhalteradressen liefern
      nichts (Tests).
- [x] Der Scanner belegt das MAC Feld vor, eine Eingabe von Hand überschreibt.
- [x] "Add Device" hat einen Knopf "Detect", aktiv bei gültiger IP.
- [x] Antwortet kein Gerät, erscheint ein Hinweis statt eines stillen Fehlers.
- [ ] In der installierten App gegen den echten TV geprüft (Scanner und
      Dialog). Erwartet: 192.168.178.25 ergibt 80:5B:65:D6:27:E0.

Stand 02.10.2026: Die Logik ist per Test belegt, der Lauf gegen den echten TV
steht aus. Ein Testprogramm außerhalb der App bekam von macOS für jeden Host
"no entry", weil die ARP Tabelle nur Prozessen mit der Freigabe Lokales
Netzwerk gezeigt wird. Die App hat diese Freigabe, ein loses Testprogramm
nicht. Belegen lässt es sich deshalb nur in der App selbst.

## Implementation plan
Phase 1: `Shared/MACAddressResolver.swift` mit `parse`, `normalize`, `lookup`
         und `resolve` (Kontakt aufnehmen, dann nachschlagen), dazu Tests.
Phase 2: `DeviceDiscovery.considerDevice` schlägt nach dem Porttest nach.
Phase 3: `DeviceScannerView` und `AddDeviceView`.

## Design decisions
- ARP Tabelle statt webOS Schnittstelle. Die MAC wird vor dem Pairing
  gebraucht, und der Mac kennt sie bereits, sobald er einmal mit dem TV
  gesprochen hat. Preis: funktioniert nur im selben Netzsegment und nur bei
  eingeschaltetem TV. Beides gilt für Wake on LAN ohnehin.
- `/usr/sbin/arp` als Prozess statt Routing Socket per `sysctl`. Der Aufruf ist
  wenige Zeilen, die Alternative wäre rund hundert Zeilen unsicherer
  Zeigerarithmetik. Preis: abhängig vom Textformat von `arp`, deshalb die Tests
  mit echten Ausgaben. In einer Sandbox ginge das nicht, die App hat keine.
- Die IP wird vor dem Aufruf validiert und als einzelnes Argument übergeben,
  nie durch eine Shell.
- Ermittelt wird die MAC der Schnittstelle, über die der TV gerade erreichbar
  ist. Hängt er im Betrieb am WLAN und im Standby am LAN, kann sie für Wake on
  LAN falsch sein. Der Hinweis im Scanner nennt deshalb den Abgleich mit den
  Einstellungen des TV.

## Risks
- Ohne die Freigabe Lokales Netzwerk findet die Erkennung nichts. Die App
  braucht sie ohnehin, um den TV zu erreichen, und zeigt bei leerem Ergebnis
  den Hinweis zur Eingabe von Hand.

## Open questions
- Keine.
