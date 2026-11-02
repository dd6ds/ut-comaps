# CoMaps für Ubuntu Touch – Portierungs-Scaffold

Click-Package-Gerüst (clickable) zum Bauen von [CoMaps](https://codeberg.org/comaps/comaps)
(fork von Organic Maps) für **Ubuntu Touch**.

> ## ⚠️ Status: Vorarbeit, kein fertiger Port
>
> Dieses Projekt liefert die komplette Build- und Packaging-Infrastruktur,
> damit CoMaps mit `clickable` gebaut und installiert werden kann. **Es wird
> aber erst funktionieren, wenn Ubuntu Touch Noble (24.04) mit Qt6 die
> Geräte erreicht** – bzw. heute schon auf Noble-Entwicklungsimages.

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
  selbst sind in CoMaps nicht übersetzt und bleiben Englisch. Die Sprache der **Kartenbeschriftung**
  stellst du weiterhin unter „Map Language“ ein.
- Die Wayland-App-ID wird auf `$APP_ID` gesetzt, damit Lomiri das Fenster der App zuordnet.

Beide Einstellungen liegen in `settings.ini` im Datenordner (`~/.local/share/ut-comaps/`).

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
- Handy mit Ubuntu Touch **Noble (24.04)**: Stable/Focal-Geräte funktionieren
  **nicht** (Qt 5.12/C++17 reicht für CoMaps nicht aus)
- Geduld: Der Build läuft arm64-emuliert (qemu). Rechne mit mehreren Stunden
  bis über Nacht. Ein nativer arm64-Rechner (z. B. Raspberry Pi 5 mit Docker)
  baut deutlich schneller.

## Bauen

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
- **Version:** Mit Tag `v1.2.3` wird die Click-Version `1.2.3`, sonst `0.1.0+git<commit>`
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

## Was nach dem ersten Build voraussichtlich noch Handarbeit braucht

1. **Framework prüfen**: gesetzt ist `ubuntu-touch-24.04-1.x`. Kontrolliere auf dem Gerät mit
   `click framework list` und passe es ggf. über `COMAPS_FRAMEWORK` an.
2. **QPA/Wayland**: Der Wrapper setzt `QT_QPA_PLATFORM=wayland`. Ob Lomiri die
   Qt6-Wayland-Session reibungslos annimmt, ist Teil der laufenden UBports-Qt6-Migration.
3. **OpenGL**: CoMaps braucht OpenGL ES. Bei Problemen das AppArmor-Log prüfen
   (`journalctl -f` bzw. `/var/log/syslog`).
4. **App-Lifecycle**: Das Qt-Widgets-Frontend kennt UTs Suspend/Resume-Semantik nicht.
5. **Größe des Clicks**: `data/` wird komplett kopiert. Mit
   `COMAPS_DATA_EXCLUDE="ordner1:ordner2" clickable build` lässt du Unnötiges weg.

## Empfehlung bis dahin

Für **fertige** Offline-OSM-Navigation auf Ubuntu Touch gibt es heute
[Pure Maps](https://puremaps.scrise.wtf/) im OpenStore.

## Lizenz / Attribution

CoMaps steht unter Apache-2.0 (siehe LICENSE im Quellrepo). Kartendaten sind
© OpenStreetMap-Mitwirkende (ODbL) – die Attribution im App-About muss
erhalten bleiben, wenn Du das Click weitergibst.
