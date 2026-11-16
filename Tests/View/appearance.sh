#!/bin/bash
# Renders screens under light and dark appearances (Adwaita on GNUstep,
# Aqua/DarkAqua on macOS) and checks resolved text/background contrast:
# every real screen must have no low-contrast finding in either; the bad
# fixture must have one in dark. Run from the repo root, after make.
set -u
fail=0
render() {  # file appearance -> prints the number of low-contrast findings
  local f=$1 ap=$2 sample=""
  [ -f "${f%.trellis}.sample.json" ] && sample="--sample ${f%.trellis}.sample.json"
  scripts/run-headless.sh obj/trellis-render "$f" $sample --widths 340,900 --height 680 \
      --theme Adwaita --appearance "$ap" --lint 2>&1 | grep -c "low-contrast"
}
for f in Examples/TrellisDemo/*.trellis dogfood/AskDetail.trellis dogfood/tickets/Blocked.trellis dogfood/tickets/Batch.trellis; do
  for ap in light dark; do
    n=$(render "$f" $ap)
    if [ "$n" != 0 ]; then echo "FAIL $f ($ap): $n low-contrast finding(s)"; fail=1; fi
  done
done
n=$(render Tests/View/fixed-background.trellis dark)
if [ "$n" = 0 ]; then echo "FAIL fixed-background (dark): expected low-contrast"; fail=1; fi
[ $fail = 0 ] && echo "APPEARANCE OK"
exit $fail
