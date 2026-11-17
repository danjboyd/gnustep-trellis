#!/bin/bash
# TrellisPreview's export and appearance, headless: --snapshot with
# --export-json writes the frames JSON (the trellis-render --json
# document, lint included), and --appearance light|dark picks the
# Adwaita colour scheme (window background light vs dark). Prints
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
for k in ("trellis", "source", "viewport", "root", "lint", "appearance"):
    assert k in d, f"missing key {k}"
bg = d["root"]["windowBackground"].lstrip("#")
lum = sum(int(bg[i:i + 2], 16) for i in (0, 2, 4)) / (3 * 255)
ok = (lum > 0.6) if ap == "light" else (lum < 0.4)
print(f"{'ok  ' if ok else 'FAIL'} {ap}: window background #{bg}, {len(d['lint'])} lint finding(s)")
sys.exit(0 if ok and d["appearance"] == ap and d["viewport"]["width"] == 520 else 1)
PY
done
rm -rf "${out:?}"
[ $fail -eq 0 ] && echo "PREVIEWEXPORT OK" || { echo "PREVIEWEXPORT FAIL"; exit 1; }
