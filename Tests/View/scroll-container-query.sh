#!/bin/bash
# Renders Tests/View/scroll-container-query.trellis at 300px with the
# default theme (a classic scroller) and checks #probe is not hidden.
set -u
# RENDER: the trellis-render command (macOS: build/trellis-render).
RENDER=${RENDER:-scripts/run-headless.sh obj/trellis-render}
out=$(mktemp -d)
$RENDER Tests/View/scroll-container-query.trellis \
  --width 300 --height 200 --json "$out/q.json" >/dev/null 2>&1
python3 -I - "$out/q.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
def find(n):
    if n.get('id') == 'probe': return n
    for c in n.get('children', []):
        r = find(c)
        if r: return r
p = find(d['root'])
ok = p is not None and not p.get('hidden', False)
print('SCROLLQUERY OK' if ok else 'SCROLLQUERY FAIL: #probe hidden by a query that tested the scroller content')
sys.exit(0 if ok else 1)
PY
rc=$?; rm -rf "$out"; exit $rc
