# Source this: . scripts/env.sh   (Trellis dev environment, private GNUSTEP_HOME)
# It sets no plain shell variables of its own (callers' P, S, etc. are left
# alone). The toolchain is TRELLIS_TOOLCHAIN, by default opt/trellis-toolchain
# in the account's home from the password database, not $HOME: callers run
# GUI tools with a private HOME (skills/trellis-mockup), and render.sh
# sources this again under it. It is exported, so a nested source finds it.
# Without TRELLIS_TOOLCHAIN and without that folder, a GNUstep already set
# up in the shell (gnustep-config on PATH) is used unchanged.
if [ -z "${TRELLIS_TOOLCHAIN:-}" ]; then
  _trellis_tc="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6)"
  _trellis_tc="${_trellis_tc:-$HOME}/opt/trellis-toolchain"
  # No Trellis toolchain there, but a GNUstep already set up in this shell
  # (MSYS2 CLANG64 with a gnustep-cli root, a distribution's GNUstep): use
  # that one as it is.
  if [ ! -d "$_trellis_tc" ] && command -v gnustep-config >/dev/null 2>&1; then
    _trellis_tc=""
  else
    TRELLIS_TOOLCHAIN=$_trellis_tc
  fi
fi
if [ -n "${TRELLIS_TOOLCHAIN:-}" ]; then
  export TRELLIS_TOOLCHAIN
  _trellis_tc=$TRELLIS_TOOLCHAIN
  export PATH="$_trellis_tc/bin:$PATH" LD_LIBRARY_PATH="$_trellis_tc/lib:${LD_LIBRARY_PATH:-}"
  export CPATH="$_trellis_tc/include" LIBRARY_PATH="$_trellis_tc/lib"
  set +u; . "$_trellis_tc/GNUstep/System/Library/Makefiles/GNUstep.sh"
fi
unset _trellis_tc
# GUI runs (tests, trellis-render) must never touch the real ~/GNUstep defaults:
# scripts/run-headless.sh runs them with HOME set to this throwaway directory.
export TRELLIS_GNUSTEP_HOME="${TRELLIS_GNUSTEP_HOME:-$HOME/.cache/trellis-gnustep-home}"
