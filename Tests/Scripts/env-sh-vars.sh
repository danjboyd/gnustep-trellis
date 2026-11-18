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
[ "$out" = "$want" ] || { echo "ENVSH FAIL: got '$out', wanted '$want'"; exit 1; }

# A private HOME (as the mockup skill asks for) must not move the
# toolchain: the default comes from the account's home, and a nested
# source after HOME changes still finds it.
priv=$(TMPDIR=/tmp mktemp -d /tmp/envh.XXXXXX)
trap 'rm -rf -- "${priv:?}"' EXIT
out=$(env -i HOME="$priv" PATH=/usr/bin:/bin bash -c '
  . scripts/env.sh >/dev/null 2>&1; command -v gnustep-config >/dev/null && echo tool')
[ "$out" = tool ] || { echo "ENVSH FAIL: with a private HOME the toolchain was not found"; exit 1; }
out=$(env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c '
  . scripts/env.sh >/dev/null 2>&1; export HOME="$1"
  bash -c ". scripts/env.sh >/dev/null 2>&1 && command -v gnustep-config >/dev/null && echo tool"' _ "$priv")
[ "$out" = tool ] || { echo "ENVSH FAIL: a nested source under a changed HOME lost the toolchain"; exit 1; }
echo "ENVSH OK"
