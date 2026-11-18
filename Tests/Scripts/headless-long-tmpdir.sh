#!/bin/bash
# run-headless.sh must work when the caller's TMPDIR is long. GNUstep puts
# local message-port sockets under TMPDIR; a long one pushed the socket
# path past the 108-byte limit and trellis-render waited forever.
#
#   Tests/Scripts/headless-long-tmpdir.sh     (after make; needs Xvfb)
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
RENDER="$REPO/obj/trellis-render"
[ -x "$RENDER" ] || { echo "headless-long-tmpdir: build trellis-render first" >&2; exit 2; }

WORK=$(TMPDIR=/tmp mktemp -d /tmp/hlt.XXXXXX)
trap 'rm -rf -- "${WORK:?}"' EXIT
LONG="$WORK/$(printf 'long-temporary-directory-%.0s' 1 2 3 4)x"
mkdir -p "$LONG"
[ ${#LONG} -gt 100 ] || { echo "FAIL test setup: TMPDIR is only ${#LONG} bytes"; exit 1; }

cat > "$WORK/s.trellis" <<'EOF'
<column><style>column { padding: 8px; }</style><label>Sample item</label></column>
EOF

export LD_LIBRARY_PATH="$REPO/obj${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
PRIVHOME="$WORK/gs"          # a stand-in private home, short enough
gdncs() { pgrep -x gdnc 2>/dev/null | wc -l; }
render() {  # $1 output name; extra env before the call
  timeout 90 "$REPO/scripts/run-headless.sh" "$RENDER" "$WORK/s.trellis" \
    --widths 200 --height 100 --png "$WORK/$1.png" >"$WORK/$1.log" 2>&1
}

fail=0
before=$(gdncs)
TMPDIR="$LONG" TRELLIS_GNUSTEP_HOME="$PRIVHOME" render a; rc=$?
if [ $rc -eq 0 ] && [ -s "$WORK/a.png" ]; then echo "ok   renders with a ${#LONG}-byte TMPDIR"
else echo "FAIL render with a ${#LONG}-byte TMPDIR (rc=$rc; 124 means it hung)"; grep -v _NET_WORKAREA "$WORK/a.log" | tail -5 | sed 's/^/     /'; fail=1; fi
TMPDIR="$LONG" TRELLIS_GNUSTEP_HOME="$PRIVHOME" render b; rc=$?
after=$(gdncs)
if [ $rc -eq 0 ] && [ "$after" -le $((before + 1)) ]; then echo "ok   a second run reuses the helper daemons (gdnc: $before before, $after after)"
else echo "FAIL second run: rc=$rc, gdnc $before before, $after after"; fail=1; fi
if [ -d "$PRIVHOME/tmp" ] && [ "$(stat -c %a "$PRIVHOME/tmp")" = 700 ]; then echo "ok   TMPDIR is the private home's tmp, mode 700"
else echo "FAIL $PRIVHOME/tmp missing or not mode 700"; fail=1; fi

DEEP="$WORK/$(printf 'deep-private-home-%.0s' 1 2 3)"
TRELLIS_GNUSTEP_HOME="$DEEP" timeout 30 "$REPO/scripts/run-headless.sh" /bin/true >"$WORK/c.log" 2>&1; rc=$?
if [ $rc -eq 3 ] && grep -q "too long" "$WORK/c.log"; then echo "ok   a too-long private home fails closed at once"
else echo "FAIL too-long private home: rc=$rc"; sed 's/^/     /' "$WORK/c.log" | tail -3; fail=1; fi

# Stop helper daemons this test started (their environment names our stand-in home).
for p in $(pgrep -x gdnc 2>/dev/null); do
  tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "GNUSTEP_HOME=$PRIVHOME" && kill "$p" 2>/dev/null
done
[ $fail -eq 0 ] && echo "HEADLESS-TMPDIR OK"
exit $fail
