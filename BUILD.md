# LGTV Companion für macOS: Bauen und Installieren

Das Projekt ist ein Swift Package. Es gibt kein Xcode Projekt, gebaut wird auf
der Kommandozeile.

## Voraussetzungen

- macOS 14.2 oder neuer (Core Audio Process Taps für das Software Volume)
- Xcode 15.2 oder neuer, oder die passenden Command Line Tools
- Swift 5.9 oder neuer

## Aufbau

```
App/                    SwiftUI App: Fenster, Menü in der Menüleiste, Anzeige
  Views/                einzelne Ansichten und Bausteine des Menüs
  Resources/            App Icon
Shared/                 Logik ohne Oberfläche (Bibliothek LGTVCompanionShared)
Tests/                  Tests der Bibliothek
scripts/                Build und Signatur
specs/features/         Spezifikation je Feature
```

## Bauen und Installieren

```bash
./scripts/build-release.sh
```

Das Skript baut die Release Version, legt `build/LGTV Companion.app` samt
`Info.plist` an, signiert sie und erzeugt ein DMG. Installieren:

```bash
cp -r "build/LGTV Companion.app" /Applications/
```

Läuft die App schon, vorher beenden und die alte Version ersetzen.

Die Versionsnummer steht an genau einer Stelle: `VERSION` in
`scripts/build-release.sh`. Die App liest sie aus ihrer `Info.plist`.

## Entwickeln

```bash
swift build          # Debug Build
swift test           # Tests
swift run LGTVCompanion
```

`swift run` startet ohne App Bundle. Dann fehlen `Info.plist` und damit die
Texte für die Freigaben von macOS: Bluetooth und System Audio funktionieren so
nicht. Für diese Funktionen immer das Bundle aus `build-release.sh` nehmen.

Die CI (`.github/workflows/build.yml`) führt bei jedem Push die Tests aus, baut
und hängt das DMG als Artefakt an. Ein Tag `v*` erzeugt ein Release.

## Lokale Signatur

macOS bindet die Freigaben für Bedienungshilfen, System Audio und Bluetooth
sowie den Zugriff auf den Schlüsselbund an die Signatur der App. Eine ad hoc
Signatur ändert sich mit jedem Build, die Freigaben gingen dann nach jedem
Update verloren.

Einmal pro Mac ausführen:

```bash
./scripts/create-signing-cert.sh
```

Das legt ein selbst signiertes Zertifikat `LGTV Companion Local Signing` im
Anmelde Schlüsselbund an. `scripts/build-release.sh` signiert damit, sobald es
vorhanden ist. Beim ersten Build fragt macOS, ob `codesign` den Schlüssel
benutzen darf: "Immer erlauben" wählen.

Prüfen:

```bash
codesign -d -r- "/Applications/LGTV Companion.app"
```

Die Ausgabe muss `certificate leaf = H"..."` enthalten. Steht dort `cdhash`,
ist die App ad hoc signiert.

Grenzen: Das Zertifikat gilt nur auf diesem Mac und ersetzt keine Developer ID.
Für die Weitergabe an andere bleibt Gatekeeper im Weg. Ohne Zertifikat (CI,
frischer Mac) signiert das Skript weiter ad hoc. Wird das Zertifikat gelöscht
und neu erzeugt, müssen die Freigaben einmal neu gesetzt werden, und macOS
fragt beim Zugriff auf den Pairing Key im Schlüsselbund nach.

## Freigaben, die die App braucht

| Freigabe | Wofür | Wann macOS fragt |
|---|---|---|
| Lokales Netzwerk | TV finden und steuern | beim ersten Start |
| Bedienungshilfen | Lautstärketasten abfangen | beim Einschalten der Option |
| Bildschirm und Systemaudio | Software Volume | beim ersten Leiserstellen |
| Bluetooth | Edifier Lautsprecher | beim Einschalten der Option |

## Fehlerbehebung

**Tasten reagieren nach einem Update nicht mehr.** Die App ist ad hoc signiert
und hat ihre Freigabe verloren. Lokale Signatur einrichten, siehe oben.

**TV wird nicht gefunden.** TV und Mac müssen im selben Netz sein, die Freigabe
Lokales Netzwerk muss erteilt sein, der TV muss eingeschaltet sein.

**Pairing läuft in einen Timeout.** Der TV zeigt beim ersten Verbinden einen
Dialog, der mit der Fernbedienung bestätigt werden muss.
