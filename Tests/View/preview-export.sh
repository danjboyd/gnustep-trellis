#!/bin/bash
# TrellisPreview's export and appearance, headless: --snapshot with
# --export-json writes the frames JSON (the trellis-render --json
# document, lint included), and --appearance light|dark picks the
# Adwaita colour scheme (window background light vs dark), checked in the
# JSON and in the PNG's pixels (scripts/png-check.py). Prints
# PREVIEWEXPORT OK.
set -u
cd "$(dirname "$0")/../.."
APP="${PREVIEW:-scripts/run-headless.sh TrellisPreview.app/TrellisPreview}"
out=$(mktemp -d)
fail=0
for ap in light dark; do
  $APP Examples/TrellisDemo/Settings.trellis --snapshot "$out/$ap.png" --export-json "$out/$ap.json" \
    --appearance "$ap" --width 520 --height 400 -GSTheme Adwaita >"$out/$ap.log" 2>&1
  if [ ! -s "$out/$ap.png" ] || [ ! -s "$out/$ap.json" ]; then
    echo "FAIL $ap: no PNG or JSON ($(grep -v _NET_WORKAREA "$out/$ap.log" | tail -1))"; fail=1; continue
  fi
  python3 -I - "$out/$ap.json" "$ap" <<'PY' || fail=1
import json, sys
d = json.load(open(sys.argv[1])); ap = sys.argv[2]
for k in ("trellis", "source", "viewport", "root", "lint", "appearance", "focusOrder"):
    assert k in d, f"missing key {k}"
bg = d["root"]["windowBackground"].lstrip("#")
lum = sum(int(bg[i:i + 2], 16) for i in (0, 2, 4)) / (3 * 255)
ok = (lum > 0.6) if ap == "light" else (lum < 0.4)
fo = d["focusOrder"]
ok = ok and isinstance(fo, list) and len(fo) >= 1   # macOS: 1 with full keyboard access off
print(f"{'ok  ' if ok else 'FAIL'} {ap}: window background #{bg}, {len(d['lint'])} lint finding(s), {len(fo)} in Tab order")
sys.exit(0 if ok and d["appearance"] == ap and d["viewport"]["width"] == 520 else 1)
PY
  # The image itself, not just the JSON: 520x400 pixels (snapshots are 1x),
  # a background that matches the appearance, and something drawn.
  python3 -I scripts/png-check.py "$out/$ap.png" --size 520x400 --appearance "$ap" || fail=1
done
# The Focus Order overlay draws over the plain snapshot.
$APP Examples/TrellisDemo/Settings.trellis --snapshot "$out/plain.png" --width 520 --height 400 >"$out/p.log" 2>&1
$APP Examples/TrellisDemo/Settings.trellis --snapshot "$out/focus.png" --focus-order --width 520 --height 400 >"$out/f.log" 2>&1
if [ -s "$out/plain.png" ] && [ -s "$out/focus.png" ] && ! cmp -s "$out/plain.png" "$out/focus.png"; then
  echo "ok   focus-order overlay drawn"
else
  echo "FAIL focus-order overlay: snapshot missing or unchanged"; fail=1
fi
# --untrusted: an image from outside the document's folder fails the load
# (exit 1), one inside renders, and without the flag the same file loads.
mkdir -p "$out/u/doc"
python3 -I - "$out/u" <<'PY'
import base64, sys
png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")
d = sys.argv[1]
open(d + "/secret.png", "wb").write(png)
open(d + "/doc/ok.png", "wb").write(png)
open(d + "/doc/out.trellis", "w").write('<column><image src="../secret.png"/><button action="terminate:">Quit</button></column>\n')
open(d + "/doc/in.trellis", "w").write('<column><image src="ok.png"/><button action="terminate:">Quit</button></column>\n')
PY
$APP --untrusted "$out/u/doc/out.trellis" --snapshot "$out/u/out.png" --width 200 --height 100 >"$out/u/out.log" 2>&1; rc_out=$?
$APP --untrusted "$out/u/doc/in.trellis" --snapshot "$out/u/in.png" --width 200 --height 100 >"$out/u/in.log" 2>&1; rc_in=$?
$APP "$out/u/doc/out.trellis" --snapshot "$out/u/trusted.png" --width 200 --height 100 >"$out/u/t.log" 2>&1; rc_t=$?
if [ $rc_out -eq 1 ] && [ $rc_in -eq 0 ] && [ -s "$out/u/in.png" ] && [ $rc_t -eq 0 ]; then
  echo "ok   --untrusted: outside image refused (exit 1), inside image renders, trusted unchanged"
else
  echo "FAIL --untrusted: exits out=$rc_out in=$rc_in trusted=$rc_t ($(grep -v _NET_WORKAREA "$out/u/out.log" | tail -1))"; fail=1
fi
rm -rf "${out:?}"
[ $fail -eq 0 ] && echo "PREVIEWEXPORT OK" || { echo "PREVIEWEXPORT FAIL"; exit 1; }
