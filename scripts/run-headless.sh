#!/bin/bash
# Runs a GNUstep GUI command (trellis-render, GUI tests) isolated from the
# real user: a private Xvfb display and a throwaway GNUSTEP_HOME/HOME.
# Fails closed if isolation cannot be set up.
#
#   scripts/run-headless.sh obj/trellis-render --screen ask --png ask.png
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/env.sh"
set -u

PRIV=${TRELLIS_GNUSTEP_HOME:-$HOME/.cache/trellis-gnustep-home}
REAL_HOME=$HOME
mkdir -p "$PRIV"
case "$(cd "$PRIV" && pwd)" in
  "$REAL_HOME"|"$REAL_HOME/GNUstep"*) echo "run-headless: private home must not be the real home" >&2; exit 3;;
esac

# GNUstep.sh unsets GNUSTEP_HOME, so set it after sourcing; gnustep-base
# reads GNUSTEP_HOME (not HOME) for NSHomeDirectory.
export GNUSTEP_HOME="$PRIV" HOME="$PRIV"
unset GNUSTEP_USER_ROOT GNUSTEP_USER_DEFAULTS_DIR || true

command -v Xvfb >/dev/null || { echo "run-headless: Xvfb not installed" >&2; exit 3; }
for n in $(seq 90 120); do
  [ -e "/tmp/.X$n-lock" ] || { DISP=":$n"; break; }
done
[ -n "${DISP:-}" ] || { echo "run-headless: no free display" >&2; exit 3; }
Xvfb "$DISP" -screen 0 1600x1200x24 -nolisten tcp >/dev/null 2>&1 &
XPID=$!
trap 'kill $XPID 2>/dev/null || true' EXIT
for i in $(seq 1 50); do [ -e "/tmp/.X11-unix/X${DISP#:}" ] && break; sleep 0.1; done
export DISPLAY="$DISP"

# Don't start gdnc/gdomap in the background from a test.
export GNUSTEP_NO_GDNC=1
"$@"
