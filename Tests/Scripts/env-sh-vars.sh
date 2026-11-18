#!/bin/bash
# scripts/env.sh must leave the caller's shell variables alone: it is
# sourced into agents' own shells (docs, skills/trellis-mockup), and a
# clobbered variable once sent an install prefix and a private
# GNUSTEP_HOME into the toolchain directory. Prints ENVSH OK.
cd "$(dirname "$0")/../.."
out=$(env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c '
  P=caller-P S=caller-S TC=caller-TC prefix=caller-prefix
  . scripts/env.sh >/dev/null 2>&1
  echo "$P|$S|$TC|$prefix|${_trellis_tc-unset}|$(command -v gnustep-config >/dev/null && echo tool)"')
want="caller-P|caller-S|caller-TC|caller-prefix|unset|tool"
if [ "$out" = "$want" ]; then echo "ENVSH OK"; else echo "ENVSH FAIL: got '$out', wanted '$want'"; exit 1; fi
