<p align="center">
  <img src="icons/ut-comaps.svg" alt="ut-comaps Icon" width="128" height="128">
</p>

# CoMaps für Ubuntu Touch

[CoMaps](https://codeberg.org/comaps/comaps) (Fork von Organic Maps) als Click-Paket für
**Ubuntu Touch**: Offline-Karten, Suche und Navigation auf Basis von OpenStreetMap – mit einer
Handy-Oberfläche im Stil der CoMaps-App fürs iPhone.

<p align="center">
  <img src="docs/screenshots/karte.jpg" alt="Karte" width="180">
  <img src="docs/screenshots/suche.jpg" alt="Suche" width="180">
  <img src="docs/screenshots/ortsdetails.jpg" alt="Ortsdetails" width="180">
</p>
<p align="center">
  <img src="docs/screenshots/menue.jpg" alt="Menü" width="180">
  <img src="docs/screenshots/ebenen.jpg" alt="Kartenebenen" width="180">
  <img src="docs/screenshots/downloader.jpg" alt="Karten herunterladen" width="180">
</p>

> **Status:** läuft auf Ubuntu Touch **24.04 (Noble)** und **26.04** (getestet auf einem
> Poco X3 Pro). Ältere Versionen (16.04/20.04) reichen für CoMaps nicht aus, siehe unten.

## Schnellstart

```bash
./build.sh ci                # auf GitHub bauen lassen (~15 min), Click nach build/ laden
./build.sh phone             # per USB/adb auf dem Handy installieren und starten
./build.sh release 0.1.0     # Release-Build mit sauberer Version (z. B. für den OpenStore)
```

Details zu `build.sh` und zum lokalen Build unter [Bauen](#bauen).

## Warum Noble (24.04)?

CoMaps (Stand: master) verlangt:

| Anforderung | UT 16.04 | UT 20.04 (Focal) | UT 24.04 (Noble) |
|---|---|---|---|
| Qt 6.4+ (Desktop-Frontend) | ❌ Qt 5.9 | ❌ Qt 5.12 | ✅ Qt 6.4 |
| C++23 (`CMAKE_CXX_STANDARD 23`) | ❌ GCC 5.4 | ❌ GCC 9.3 | ✅ GCC 13 |
| CMake ≥ 3.22.1 | ❌ | ⚠️ nur via Kitware-PPA | ✅ 3.28 |
| FreeType ≥ 2.13.1 | ❌ | ❌ (2.10) | ✅ 2.13.2 |

Noble ist die erste UT-Basis, die alle offiziellen Abhängigkeiten des
CoMaps-Desktop-Builds aus dem Ubuntu-Repository deckt (`qt6-base-dev`,
`qt6-positioning-dev`, `qt6-svg-dev`, …). Die Qt6-Migration von UBports läuft
parallel dazu (u. a. Morph-Browser mit gebündeltem Qt6).

## Ubuntu-Touch-Anpassungen (patches/)

CoMaps bringt nur ein Qt-Widgets-Desktop-Frontend mit. `patches/0001-ut-integration-theme-language.patch`
ergänzt es für Ubuntu Touch (neue Datei `qt/ut_integration.{hpp,cpp}`):

- **Darstellung (Darkmode):** In *Preferences → Appearance* gibt es „Like the phone“, „Light“ und „Dark“.
  Die Einstellung gilt für die Bedienoberfläche (Fusion-Stil mit heller oder dunkler Palette) und für
  den Kartenstil. „Like the phone“ liest das Lomiri-Theme aus
  `~/.config/lomiri-ui-toolkit/theme.ini` (z. B. SuruDark) und schaltet live mit, wenn du es in den
  Systemeinstellungen umstellst. Das ersetzt den reinen Karten-Schalter „Map Appearance“ von CoMaps.
- **Sprache:** In *Preferences → Language (after restart)* wählst du „Like the phone“ oder eine
  feste Sprache. Sie bestimmt die CoMaps-Texte (Suche und Kategorien, Ortstypen, Routing-Hinweise,
  Ländernamen) und wird beim nächsten Start übernommen. Die Beschriftungen der Desktop-Oberfläche
  selbst übersetzt CoMaps nicht; die Handy-Oberfläche (siehe unten) bringt eigene deutsche und
  englische Texte mit. Die Sprache der **Kartenbeschriftung**
  stellst du weiterhin unter „Map Language“ ein.
- Die Wayland-App-ID wird auf `$APP_ID` gesetzt, damit Lomiri das Fenster der App zuordnet.

Beide Einstellungen liegen in `settings.ini` im Datenordner (`~/.local/share/ut-comaps/`).

### Handy-Oberfläche im Stil der iPhone-App (`patches/0006-ut-mobile-ui-ios-style.patch`)

Die Desktop-Werkzeugleiste und das Menü passen nicht auf ein Handy. Stattdessen liegt die Karte
bildschirmfüllend unter runden, schwebenden Bedienelementen – wie in der CoMaps-App fürs iPhone:

- oben: Menü (⋯), Verkehrsmittel (zu Fuß, Rad, Auto, ÖPNV), Kartenebenen (Outdoor, Höhenlinien,
  3D-Gebäude, ÖPNV-Linien)
- unten: Lesezeichen (★), Suchfeld „Suche“, Mein Standort
- Suche als eigene Seite mit Kategorien, Treffern (Name, Typ, Adresse, Entfernung) und „Abbrechen“
- Ortsdetails als Blatt von unten (Einwohner, Adresse, Öffnungszeiten, Telefon, Web, Koordinaten)
  mit „Route von“, „Speichern“, „Route nach“, „Bearbeiten“
- Routen-Zusammenfassung („35 min • 35 km“) mit „Start“, Download-Banner für die sichtbare Region
- Vollbild-Dialoge (Karten herunterladen, Lesezeichen, Einstellungen …) bekommen eine Kopfzeile mit
  rundem Zurück-Knopf und Titel; Listen scrollen mit dem Finger

Solange die App im Vordergrund ist, dimmt und sperrt das Display nicht (repowerd
`keepDisplayOn`, AppArmor-Gruppe `keep-display-on`); im Hintergrund gilt wieder das normale Verhalten.

Die Texte folgen der Sprache (Deutsch/Englisch), die Farben dem hellen/dunklen Erscheinungsbild.
Die Bedienelemente sind Geschwister des Karten-Widgets (nicht Kinder): die Karte nimmt Touch-Ereignisse
selbst an und würde sonst alle Berührungen schlucken.

`patches/0007-…` macht Downloads robuster (30-s-Timeout, falls ein Spiegelserver nicht antwortet)
und übersetzt Ortstypen („Großstadt“ statt „City“) mit den Texten der iPhone-App.

**UI-Tests über adb:** Mit gesetzter Umgebungsvariable `UT_COMAPS_TEST=<datei>` führt die App
Befehle aus, die in diese Datei geschrieben werden (`click <objectName>`, `clicktext <text>`,
`tap <x> <y>`, `type <text>`, `back`, `dump`, `center <lat> <lon> <zoom>` …), Ausgaben landen in
`<datei>.out`. Ohne die Variable ist nichts davon aktiv.

Die Patches sind gegen einen festen CoMaps-Commit erstellt (`COMAPS_REF` in
`scripts/fetch-source.sh`). `scripts/apply-patches.sh` wendet sie beim Bauen an und überspringt
bereits angewendete Patches.

## Projektstruktur

```
ut-comaps/
├── clickable.json          # clickable-Konfiguration (custom builder, arm64, Noble-Framework)
├── Dockerfile.noble-arm64  # Build-Container: ubuntu:24.04 + Qt6 + Toolchain
├── manifest.in.json        # Click-Manifest (Vorlage), App-Name „ut-comaps“
├── ut-comaps.desktop       # Desktop-Entry für den App-Launcher
├── ut-comaps.apparmor      # AppArmor-Policy (networking, location, …)
├── icons/ut-comaps.svg     # App-Icon (SVG, 256×256)
├── launch/comaps           # Start-Wrapper: Qt6-Libs, Wayland, Skalierung, Datenpfade
├── patches/                # Ubuntu-Touch-Anpassungen an CoMaps (Darkmode, Sprache)
├── .github/workflows/      # GitHub-Actions-Build (arm64-Runner) + Releases
└── scripts/
    ├── fetch-source.sh     # CoMaps-Quellen am festen Commit holen (shallow/partial)
    ├── apply-patches.sh    # patches/*.patch anwenden (wiederholbar)
    ├── build-comaps.sh     # Patches + configure.sh + tools/unix/build_omim.sh -r desktop
    └── package.sh          # Click-Verzeichnis zusammenstellen (Libs, Plugins, Daten)
```

## Voraussetzungen

- Linux-Host mit Docker und **clickable ≥ 8** (`pip install clickable-ut`)
- mind. 30 GB freier Platz, gute Internetverbindung
- Handy mit Ubuntu Touch **24.04 (Noble)** oder **26.04**: Stable/Focal-Geräte funktionieren
  **nicht** (Qt 5.12/C++17 reicht für CoMaps nicht aus)
- Für GitHub-Builds (`./build.sh ci` / `release`): gespeicherte Git-Zugangsdaten für github.com
  oder `GH_TOKEN`
- Für den lokalen Build Geduld: Er läuft arm64-emuliert (qemu). Rechne mit mehreren Stunden
  bis über Nacht. Ein nativer arm64-Rechner (z. B. Raspberry Pi 5 mit Docker)
  baut deutlich schneller.

## Bauen

### build.sh

`build.sh` braucht auf dem Rechner nur Docker (clickable läuft selbst im Container
`clickable-runner`, wie bei den anderen UT-Projekten) und für die Installation `adb`:

| Aufruf | Was passiert |
|---|---|
| `./build.sh ci` | startet den GitHub-Build, wartet und lädt das Click nach `build/` (Version `0.1.0.<Lauf>`) |
| `./build.sh release <version>` | setzt das Tag `v<version>`, GitHub baut und veröffentlicht ein Release mit genau dieser Version, das Click landet in `build/` |
| `./build.sh download` | lädt das Click des neuesten GitHub-Releases nach `build/` |
| `./build.sh phone [datei.click]` | installiert das neueste Click aus `build/` (oder das angegebene) per adb und startet die App |
| `./build.sh` | lokaler Build mit clickable (baut die Docker-Images bei Bedarf, holt die Quellen) |
| `./build.sh local-phone` | lokaler Build, danach installieren |
| `./build.sh <clickable-Argumente>` | beliebiger clickable-Befehl, z. B. `script source`, `clean` |

Auf Images ohne `pkcon` (z. B. UT 26.04) installiert `phone` mit `sudo click install`; das Handy
fragt dann im Terminal nach seinem Passwort.

`ci` und `release` laden das Click aus dem Workflow-Artefakt des Laufs. Darf der Workflow kein
GitHub-Release anlegen (GitHub antwortete zeitweise mit HTTP 403), legt `release` es mit deinem
Token selbst an.

**OpenStore:** Für einen Upload `./build.sh release 0.1.0` (danach `0.1.1`, `0.2.0` …). Der
OpenStore verlangt bei jedem Upload eine höhere Version als die vorige.

Die folgenden Abschnitte beschreiben, was `build.sh` für den lokalen Build tut – zum Nachvollziehen
oder wenn du es von Hand machen willst.

### 1) Docker-Image für clickable bauen (einmalig)

clickable baut nicht in seinem Standard-Image (das basiert auf 20.04), sondern in einem eigenen
Noble-Image mit Qt6 und der CoMaps-Toolchain. `clickable.json` verweist per
`"docker_image": "ut-comaps:noble-arm64"` darauf, das Image muss also unter genau diesem Namen
lokal vorhanden sein, bevor du `clickable` aufrufst.

Auf einem amd64-Rechner läuft der arm64-Container per qemu. Einmalig einrichten:

```bash
sudo apt install qemu-user-static binfmt-support
# Test: muss "aarch64" ausgeben
docker run --rm --platform linux/arm64 ubuntu:24.04 uname -m
```

Dann das Image bauen:

```bash
cd ut-comaps
docker build --platform linux/arm64 -t ut-comaps:noble-arm64 -f Dockerfile.noble-arm64 .
docker images ut-comaps   # Kontrolle: Tag noble-arm64 vorhanden
```

Neu bauen musst du das Image nur, wenn sich `Dockerfile.noble-arm64` ändert
(`docker build --no-cache …` erzwingt einen frischen Stand der Pakete).

Typische Fehler:

| Meldung | Ursache / Lösung |
|---|---|
| `exec format error` | qemu/binfmt fehlt, siehe oben |
| `pull access denied for ut-comaps` | Image noch nicht gebaut oder anderer Tag als in `clickable.json` |
| `"arch" is no longer a valid configuration option` | clickable 8 kennt `arch` nicht mehr; die Architektur steht in `restrict_arch` |

### 2) Quellen holen, bauen, installieren

```bash
# CoMaps-Quellen am gepinnten Commit holen (mehrere GB):
clickable script source

# Bauen + packen (wendet die Patches an, dauert unter qemu Stunden):
clickable build --arch arm64

# Auf dem Handy installieren (Gerät per adb/usb verbunden):
clickable install --arch arm64
```

Eine Shell im Build-Container (zum Debuggen) gibt es mit `clickable script shell`.

Ohne clickable geht es auch direkt im Container:

```bash
docker run --rm -it --platform linux/arm64 -v "$PWD":/project ut-comaps:noble-arm64 \
    scripts/build-comaps.sh
```

Das baut und packt nach `build/*.click`.

## GitHub Actions

`.github/workflows/build.yml` baut das Click auf GitHub, genau wie lokal (selbes Dockerfile,
`scripts/fetch-source.sh` + `scripts/build-comaps.sh`), aber ohne qemu:

- **Runner:** `ubuntu-24.04-arm` (nativ arm64, für öffentliche Repos kostenlos). Ein Build dauert
  so etwa 1–2 Stunden statt einer Nacht und bleibt unter dem 6-Stunden-Limit von GitHub.
- **Start:** manuell unter *Actions → Build click → Run workflow* (optional mit Release) oder
  per Tag: `git tag v0.1.0 && git push --tags` baut und veröffentlicht ein Release.
- **Version:** Mit Tag `v1.2.3` wird die Click-Version `1.2.3`, sonst `0.1.0.<Laufnummer>`
  (`BASE_VERSION` im Workflow).
- **Ergebnis:** `ut-comaps_<version>_arm64.click` plus `SHA256SUMS` als Workflow-Artefakt
  (30 Tage) und bei Releases im GitHub-Release, mit Installationsanleitung.
- **ccache:** Der Compiler-Cache wird zwischen den Läufen gespeichert, Folgebuilds sind deutlich
  schneller. Lokal liegt er unter `.ccache/` (in `.gitignore`).
- **Quellen:** Im Workflow kommt CoMaps vom GitHub-Spiegel (`COMAPS_GIT_URL`), lokal von Codeberg.

## Laufzeit-Details

- **Datenpfade:** Ressourcen (Stile, Schriften, World.mwm) kommen schreibgeschützt aus dem Click
  (`-resources_path`). Heruntergeladene Karten, Lesezeichen und Einstellungen landen in
  `~/.local/share/ut-comaps/` (`-data_path`), dem einzigen beschreibbaren Ort für die App.
- **Skalierung:** Der Wrapper setzt `QT_SCALE_FACTOR = GRID_UNIT_PX / 8`, damit die
  Qt-Widgets so groß sind wie native Apps.
- **Bibliotheken:** `package.sh` bündelt Qt6 und dessen Abhängigkeiten, aber bewusst **nicht**
  libc/libstdc++, EGL/GLES/GL, Wayland, DRM, D-Bus und systemd. Die müssen vom Handy kommen,
  sonst bricht das GPU-Rendering über libhybris.

## Bekannte Punkte

- **Framework:** gesetzt ist `ubuntu-touch-24.04-1.x` (läuft auch auf 26.04). Kontrolle auf dem
  Gerät mit `click framework list`, anpassen über `COMAPS_FRAMEWORK`.
- **Neuere Images (26.04):** Der Launcher vergrößert die statische TLS-Reserve von glibc
  (sonst lädt libhybris den Android-Linker nicht) und `package.sh` bündelt eine zur gebündelten
  libcrypto passende libssl (sonst „TLS initialization failed“ beim Kartendownload).
- **Bildschirmtastatur:** Der Launcher übergibt dem Maliit-Plugin die Serveradresse direkt
  (`MALIIT_SERVER_ADDRESS`); die Abfrage per D-Bus erreicht das Plugin unter Qt 6 nicht.
- **Display:** Solange die App im Vordergrund ist, wird der Bildschirm nicht gedimmt oder gesperrt.
- **Größe des Clicks:** `data/` wird komplett kopiert. Mit
  `COMAPS_DATA_EXCLUDE="ordner1:ordner2" ./build.sh` lässt du Unnötiges weg.
- **Icons:** `icons/ut-comaps.svg` ist das App-Icon, `icons/ut-comaps-v1.svg` das frühere.

## Lizenz / Attribution

CoMaps steht unter Apache-2.0 (siehe LICENSE im Quellrepo). Kartendaten sind
© OpenStreetMap-Mitwirkende (ODbL) – die Attribution im App-About muss
erhalten bleiben, wenn Du das Click weitergibst.
