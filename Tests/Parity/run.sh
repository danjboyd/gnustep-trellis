#!/bin/bash
# Platform parity matrix for TrellisPreview (docs/windows.md): runs the same
# cases on Linux and on Windows (MSYS2 CLANG64) and writes everything to
# OUT, plus OUT/manifest.json. Tests/Parity/compare.py then compares two
# OUT folders (one per platform). Synthetic fixture only (Parity.trellis).
#
#   Tests/Parity/run.sh OUT        (from a built checkout; OUT must be new)
#
# Cases, for each theme in THEMES (default "Adwaita") and appearance
# (light, dark; dark only where the theme has one, i.e. Adwaita):
#   open     TrellisPreview --snapshot + --export-json at 900x640
#   resize   the same window resized live to 520x640 and 340x640 (--resize)
#   reload   --watch 2: the fixture edited, then its sample, while it polls
#   render   trellis-render at 900, with the same theme and appearance;
#            its PNG must equal the TrellisPreview snapshot pixel for pixel
#            (same platform and build)
# And once:
#   refuse   trellis-render refuses (exit 3) without a private GNUSTEP_HOME.
#            HOME (and USERPROFILE on Windows) point at a stand-in folder, so
#            even a broken guard could only touch that; the path rules
#            themselves are tested on stand-in trees in make check
#            (Tests/View/isolation-verdict.m), never on the real home
#   settings the real ~/GNUstep is unchanged by the whole run
#   registry (Windows) whether HKCU\Software\GNUstep or
#            HKCU\Software\GNUstepNSMessagePort changed. Reported as INFO,
#            not a failure: gnustep-base writes message-port names there on
#            every launch, whatever the private home, and whether that's
#            acceptable is Dan's decision (ask #8624)
# Exit 0 when every case passes; the manifest lists each case either way.
set -u
cd "$(dirname "$0")/../.."
OUT=${1:?usage: Tests/Parity/run.sh OUT}
[ -e "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ] && { echo "run.sh: $OUT is not empty" >&2; exit 2; }
mkdir -p "$OUT/work" && OUT=$(cd "$OUT" && pwd)
. scripts/env.sh >/dev/null 2>&1
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) PLATFORM=windows; EXE=.exe ;; *) PLATFORM=linux; EXE= ;; esac
export LD_LIBRARY_PATH="$PWD/obj${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" PATH="$PWD/obj:$PATH"
PY=$(command -v python3 || command -v python || true)   # Windows: the runner's python is fine
[ -n "$PY" ] || { echo "run.sh: needs python3 (or python) for the pixel check and the manifest" >&2; exit 2; }
RUN=scripts/run-headless.sh
PREVIEW=./TrellisPreview.app/TrellisPreview$EXE
RENDER=./obj/trellis-render$EXE
THEMES=${THEMES:-Adwaita}
FIX=Tests/Parity/Parity.trellis
if [ $PLATFORM = windows ]; then REALGS="$(cygpath -u "$USERPROFILE")/GNUstep"
else REALGS="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6)"; REALGS="${REALGS:-$HOME}/GNUstep"; fi
cases=()                      # name|status|detail
add() { cases+=("$1|$2|$3"); printf '%-6s %s  %s\n' "$2" "$1" "$3"; }

settings_state() {  # the real GNUstep settings folder: must not change
  find "$REALGS" -printf '%P %s %T@\n' 2>/dev/null | sort | sha256sum | cut -d' ' -f1
}
registry_state() {  # Windows only: reported, not failed (ask #8624)
  [ $PLATFORM = windows ] && command -v reg >/dev/null || { echo n/a; return; }
  for k in 'HKCU\Software\GNUstep' 'HKCU\Software\GNUstepNSMessagePort'; do
    echo "== $k"; MSYS2_ARG_CONV_EXCL='*' reg query "$k" /s 2>/dev/null
  done | tee -a "$OUT/registry.txt" | sha256sum | cut -d' ' -f1
}
before=$(settings_state); reg_before=$(registry_state)

for theme in $THEMES; do
  aps="light"; [ "$theme" = Adwaita ] && aps="light dark"
  for ap in $aps; do
    tag="$theme-$ap"
    # open + resize
    if timeout 120 $RUN "$PREVIEW" "$FIX" --snapshot "$OUT/open-$tag.png" --export-json "$OUT/open-$tag.json" \
         --width 900 --height 640 --resize 520x640,340x640 --appearance "$ap" -GSTheme "$theme" \
         > "$OUT/open-$tag.log" 2>&1 && [ -s "$OUT/open-$tag.png" ] && [ -s "$OUT/open-$tag.json" ]; then
      add "open $tag" PASS "open-$tag.png/.json"
    else add "open $tag" FAIL "see open-$tag.log"; fi
    if [ -s "$OUT/open-$tag-520x640.json" ] && [ -s "$OUT/open-$tag-340x640.json" ]; then
      add "resize $tag" PASS "open-$tag-520x640, open-$tag-340x640"
    else add "resize $tag" FAIL "no resize snapshots (see open-$tag.log)"; fi
    # render, and the same-platform pixel check
    if timeout 120 $RUN "$RENDER" "$FIX" --sample Tests/Parity/Parity.sample.json --widths 900 --height 640 \
         --theme "$theme" --appearance "$ap" --png "$OUT/render-$tag.png" --json "$OUT/render-$tag.json" \
         > "$OUT/render-$tag.log" 2>&1; then
      if "$PY" -I Tests/Parity/compare.py --pixels "$OUT/render-$tag.png" "$OUT/open-$tag.png" > "$OUT/pixels-$tag.txt" 2>&1; then
        add "render $tag" PASS "$(cat "$OUT/pixels-$tag.txt")"
      else add "render $tag" FAIL "$(tail -1 "$OUT/pixels-$tag.txt")"; fi
    else add "render $tag" FAIL "see render-$tag.log"; fi
  done
done

# reload: edit the fixture, then its sample, while Preview polls them
W="$OUT/work"; cp "$FIX" Tests/Parity/Parity.sample.json "$W/"
( timeout 90 $RUN "$PREVIEW" "$W/Parity.trellis" --snapshot "$OUT/reload.png" --export-json "$OUT/reload.json" \
    --width 900 --height 640 --watch 2 --watch-timeout 60 -GSTheme Adwaita > "$OUT/reload.log" 2>&1
  echo $? > "$W/reload.rc" ) &
sleep 5; sed -i 's/Parity sample</Parity sample (edited)</' "$W/Parity.trellis"
sleep 3; sed -i 's/"countA": "7"/"countA": "8"/' "$W/Parity.sample.json"
wait
if [ "$(cat "$W/reload.rc" 2>/dev/null)" = 0 ] && grep -q 'Parity sample (edited)' "$OUT/reload-reload1.json" 2>/dev/null \
   && grep -q '"8"' "$OUT/reload-reload2.json" 2>/dev/null; then
  add "reload" PASS "reload-reload1 has the edited title, reload-reload2 the edited sample"
else add "reload" FAIL "see reload.log (rc $(cat "$W/reload.rc" 2>/dev/null))"; fi

# refuse: no private GNUSTEP_HOME, no render (a stand-in HOME either way)
SI="$OUT/standin-home"; mkdir -p "$SI"
if [ $PLATFORM = windows ]; then SIH="$(cygpath -w "$SI")"; else SIH="$SI"; fi
env -u GNUSTEP_HOME -u DISPLAY HOME="$SIH" USERPROFILE="$SIH" timeout 30 "$RENDER" "$FIX" --widths 900 \
  --png "$OUT/refuse.png" > "$OUT/refuse.log" 2>&1; r=$?
if [ $r = 3 ] && [ ! -e "$OUT/refuse.png" ] && grep -q 'refusing to run' "$OUT/refuse.log"; then
  add "refuse" PASS "exit 3 without a private GNUSTEP_HOME; nothing written"
else add "refuse" FAIL "exit $r (want 3); see refuse.log"; fi

after=$(settings_state); reg_after=$(registry_state)
[ "$before" = "$after" ] && add "settings" PASS "the real $REALGS is unchanged" \
  || add "settings" FAIL "the real $REALGS changed during the run"
if [ "$reg_before" = n/a ]; then add "registry" INFO "not Windows"
elif [ "$reg_before" = "$reg_after" ]; then add "registry" INFO "HKCU GNUstep keys unchanged"
else add "registry" INFO "HKCU GNUstep keys changed (registry.txt has before and after; ask #8624)"; fi

"$PY" -I - "$OUT/manifest.json" "$PLATFORM" "$(git rev-parse HEAD 2>/dev/null)" "$THEMES" "${cases[@]}" <<'PY'
import json, sys
out, platform, commit, themes, *cases = sys.argv[1:]
rows = [dict(zip(("case", "status", "detail"), c.split("|", 2))) for c in cases]
json.dump({"platform": platform, "commit": commit, "themes": themes.split(), "cases": rows},
          open(out, "w"), indent=1)
PY
fails=$(printf '%s\n' "${cases[@]}" | grep -c '|FAIL|'); passes=$(printf '%s\n' "${cases[@]}" | grep -c '|PASS|')
echo "== $PLATFORM: $passes passed, $fails failed, $(( ${#cases[@]} - passes - fails )) info (manifest: $OUT/manifest.json)"
[ "$fails" = 0 ]
