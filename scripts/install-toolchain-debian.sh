#!/bin/bash
# Builds the Trellis dev toolchain on Debian 13: clang + libobjc2 + libdispatch +
# GNUstep make/base/gui/back (ng-gnu-gnu, ARC). Installs into $PREFIX (no root needed).
# apt build deps are listed in docs/building.md.
set -euo pipefail
SRC=${SRC:-$HOME/src/gnustep}
J=${J:-$(nproc)}
PREFIX=${PREFIX:-$HOME/opt/trellis-toolchain}
mkdir -p "$PREFIX"
export PATH="$PREFIX/bin:$PATH" LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"
export CPATH="$PREFIX/include" LIBRARY_PATH="$PREFIX/lib" PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
# Passed to each configure as arguments too, so autoconf records them (they
# survive a reconfigure or a clean environment): without -L$PREFIX/lib first,
# gobjc's libobjc (Debian 13, gcc 14) shadows libobjc2 at link time.
CONF_FLAGS=("CPPFLAGS=$CPPFLAGS" "LDFLAGS=$LDFLAGS")
export CC=clang CXX=clang++
mkdir -p "$SRC"; cd "$SRC"
clone() { [ -d "$2" ] || git clone --depth 1 ${3:-} "https://github.com/$1" "$2"; }
clone gnustep/libobjc2 libobjc2 --recursive
clone swiftlang/swift-corelibs-libdispatch libdispatch
clone gnustep/tools-make tools-make
clone gnustep/libs-base libs-base
clone gnustep/libs-gui libs-gui
clone gnustep/libs-back libs-back

echo "== libobjc2"; cd "$SRC/libobjc2"; mkdir -p build; cd build
cmake .. -GNinja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DTESTS=OFF -DCMAKE_INSTALL_PREFIX="$PREFIX"
ninja && ninja install

echo "== libdispatch"; cd "$SRC/libdispatch"; mkdir -p build; cd build
cmake .. -GNinja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DINSTALL_PRIVATE_HEADERS=YES -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX="$PREFIX"
ninja && ninja install

echo "== tools-make"; cd "$SRC/tools-make"
./configure --with-library-combo=ng-gnu-gnu --enable-objc-arc --enable-native-objc-exceptions --with-layout=gnustep --prefix="$PREFIX/GNUstep" "${CONF_FLAGS[@]}"
make && make install
set +u; . "$PREFIX/GNUstep/System/Library/Makefiles/GNUstep.sh"; set -u

echo "== libs-base"; cd "$SRC/libs-base"; ./configure "${CONF_FLAGS[@]}"; make -j$J && make install
echo "== libs-gui";  cd "$SRC/libs-gui";  ./configure "${CONF_FLAGS[@]}"; make -j$J && make install
echo "== libs-back"; cd "$SRC/libs-back"; ./configure --enable-graphics=cairo "${CONF_FLAGS[@]}"; make -j$J && make install
echo "== DONE"
