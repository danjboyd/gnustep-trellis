# Source this: . scripts/env.sh   (Trellis dev environment, private GNUSTEP_HOME)
P=${TRELLIS_TOOLCHAIN:-$HOME/opt/trellis-toolchain}
export PATH="$P/bin:$PATH" LD_LIBRARY_PATH="$P/lib:${LD_LIBRARY_PATH:-}"
export CPATH="$P/include" LIBRARY_PATH="$P/lib"
set +u; . "$P/GNUstep/System/Library/Makefiles/GNUstep.sh"
# GUI runs (tests, trellis-render) must never touch the real ~/GNUstep defaults:
# scripts/run-headless.sh runs them with HOME set to this throwaway directory.
export TRELLIS_GNUSTEP_HOME="${TRELLIS_GNUSTEP_HOME:-$HOME/.cache/trellis-gnustep-home}"
