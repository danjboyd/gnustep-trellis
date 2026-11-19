# Building Trellis

## GNUstep (Debian 13)

Trellis needs clang, libobjc2 (the GNUstep runtime, with ARC and blocks),
libdispatch and GNUstep make/base/gui/back. GCC and the GCC Objective-C
runtime are not supported.

1. **Build dependencies.** These are the packages installed on the
   development VM where Trellis is built and tested:

   ```sh
   sudo apt-get install --no-install-recommends \
     clang lld cmake ninja-build pkg-config git python3 xvfb imagemagick \
     libffi-dev libxml2-dev libxslt1-dev libgnutls28-dev libicu-dev \
     libcurl4-gnutls-dev zlib1g-dev libavahi-client-dev libbsd-dev libgmp-dev \
     libcairo2-dev libxt-dev libxext-dev libxft-dev libfreetype-dev \
     libfontconfig-dev libjpeg-dev libtiff-dev libpng-dev libgif-dev libxrandr-dev
   ```

   `xvfb` is only for `make check-gui` and `trellis-render` (headless
   renders), and `imagemagick` only for assembling comparison images.
2. **Toolchain.** `scripts/install-toolchain-debian.sh` builds libobjc2,
   libdispatch and GNUstep from source into `~/opt/trellis-toolchain`, with
   no root needed. Override the location with `PREFIX=...`.
3. **Trellis.**

   ```sh
   . scripts/env.sh
   make            # or make -j; make shared=no for static Trellis libraries
   make check      # engine cases, lint, markup, conformance report
   make check-gui  # view checks, headless under Xvfb
   ```

Then [tutorial.md](tutorial.md) builds a first app against the installed
Trellis (`make install`). `scripts/check-tutorial.sh` runs the tutorial
end to end, as CI does.

GUI runs (`trellis-render`, `make check-gui`) go through
`scripts/run-headless.sh`, which uses a private Xvfb display and a private
`GNUSTEP_HOME`, so they never touch your real defaults or display.

## macOS

Plain Apple clang (Command Line Tools); no Xcode project or GNUstep needed:

```sh
make -f Makefile.macos check   # engine and conformance
make -f Makefile.macos gui     # libTrellis, the tools and TrellisPreview.app
```

The other checks, all headless (no window is ordered front, so they run
over ssh); each builds what it needs:

```sh
make -f Makefile.macos check-view       # every Tests/View test under NSZombieEnabled, scroll query, markup lint
make -f Makefile.macos check-preview    # TrellisPreview snapshot and frames export, light and dark
make -f Makefile.macos check-reference  # frame replay of the golden dumps, with self-test
make -f Makefile.macos check-migration  # the frames that changed from 0.5.x to 0.7
# 0.7 to 0.8: docs/migration-0.8.md (position: static only)
make -f Makefile.macos check-importers  # conformance importer unit tests (Python only)
python3 -I scripts/conformance-summary.py check --platform macos --runner build/trellis-case
```

The last line is the conformance gate CI runs: it fails if a suite passes
fewer cases than `docs/conformance/macos.json` records. On a fresh clone
the whole set takes under a minute on an M-series Mac with `make -j2`.

### Headless Preview export (macOS)

TrellisPreview can write a snapshot and its frames JSON without showing a
window, so it runs over ssh. Use a copy of the app marked `LSUIElement`
so no Dock icon appears (`make -f Makefile.macos check-preview` makes one
in `build/preview-check`):

```sh
make -f Makefile.macos gui
mkdir -p build/preview-check && cp -R build/TrellisPreview.app build/preview-check/
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' build/preview-check/TrellisPreview.app/Contents/Info.plist
P=build/preview-check/TrellisPreview.app/Contents/MacOS/TrellisPreview
$P Screen.trellis --snapshot out.png --export-json out.json \
   --appearance dark --width 340 --height 680
```

- `Screen.sample.json` beside the spec is applied, as in the window.
- `--appearance light|dark` sets the window's and content view's
  appearance. `--width`/`--height` set the content size in points; the
  default is 640 x 480. `--focus-order` draws the Tab-order overlay into
  the snapshot.
- The PNG is drawn at **1x**: its pixel size equals the point size
  (340 x 680 above), whatever the screen's backing scale.
- Repeat exports are **byte-identical**, PNG and JSON, for the same spec,
  size and appearance (checked on the controls and migration fixtures,
  two widths, both appearances, three runs each).
- `--untrusted` (since 0.10.2), placed before the file, loads it hardened,
  for files someone else sent: images only from the document's own
  folder, standard view classes only, and controls and links that do
  nothing when clicked. A path rule broken is a load failure (exit 1).
  See `TRMarkupDocument.untrusted` in TRMarkup.h.
- **Exit status:** 0 on success; 1 when the spec or its sample fails to
  load (the snapshot then shows the error message, and no JSON is
  written); 2 for an `--appearance` other than `light` or `dark`.
