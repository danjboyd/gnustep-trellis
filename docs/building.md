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

GUI runs (`trellis-render`, `make check-gui`) go through
`scripts/run-headless.sh`, which uses a private Xvfb display and a private
`GNUSTEP_HOME`, so they never touch your real defaults or display.

## macOS

Plain Apple clang (Command Line Tools); no Xcode project or GNUstep needed:

```sh
make -f Makefile.macos check   # engine and conformance
make -f Makefile.macos gui     # libTrellis, the tools and TrellisPreview.app
```
