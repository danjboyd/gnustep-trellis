#!/bin/bash
# Renders screens under light and dark appearances (Adwaita on GNUstep,
# Aqua/DarkAqua on macOS) and checks resolved text/background contrast:
# every real screen must have no low-contrast finding in either; the bad
# fixture must have one in dark. Run from the repo root, after make.
set -u
fail=0
# On GNUstep the checks need the Adwaita theme; without it every count is
# misleading, so say so and fail.
if [ "$(uname)" != Darwin ]; then
  . scripts/env.sh >/dev/null 2>&1 || true
  priv=${TRELLIS_GNUSTEP_HOME:-$HOME/.cache/trellis-gnustep-home}
  found=""
  for d in "$priv/GNUstep/Library/Themes" \
           "$(gnustep-config --variable=GNUSTEP_LOCAL_LIBRARY 2>/dev/null)/Themes" \
           "$(gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARY 2>/dev/null)/Themes" \
           "$(gnustep-config --variable=GNUSTEP_NETWORK_LIBRARY 2>/dev/null)/Themes"; do
    [ -d "$d/Adwaita.theme" ] && found="$d" && break
  done
  if [ -z "$found" ]; then
    echo "APPEARANCE FAIL: Adwaita theme not installed (looked in the private GNUSTEP_HOME and the LOCAL/SYSTEM/NETWORK Themes folders)"
    exit 1
  fi
fi
render() {  # file appearance -> prints the number of low-contrast findings, or CRASH
  local f=$1 ap=$2 sample="" out rc
  [ -f "${f%.trellis}.sample.json" ] && sample="--sample ${f%.trellis}.sample.json"
  out=$(${RENDER:-scripts/run-headless.sh obj/trellis-render} "$f" $sample --widths 340,900 --height 680 \
      --theme Adwaita --appearance "$ap" --lint 2>&1)
  rc=$?
  # A crash prints no findings, so check the exit status and the summary line.
  if [ $rc -ne 0 ] || ! grep -q "lint finding(s)" <<<"$out"; then echo "CRASH(rc=$rc)"; return; fi
  grep -c "low-contrast" <<<"$out"
}
for f in Examples/TrellisDemo/*.trellis dogfood/AskDetail.trellis dogfood/tickets/Blocked.trellis dogfood/tickets/Batch.trellis dogfood/work/Work.trellis dogfood/desk/*.trellis Tests/View/mark.trellis; do
  for ap in light dark; do
    n=$(render "$f" $ap)
    if [ "${n#CRASH}" != "$n" ]; then echo "FAIL $f ($ap): trellis-render $n"; fail=1
    elif [ "$n" != 0 ]; then echo "FAIL $f ($ap): $n low-contrast finding(s)"; fail=1; fi
  done
done
n=$(render Tests/View/fixed-background.trellis dark)
if [ "$n" = 0 ] || [ "${n#CRASH}" != "$n" ]; then echo "FAIL fixed-background (dark): expected low-contrast, got $n"; fail=1; fi
[ $fail = 0 ] && echo "APPEARANCE OK"
exit $fail
