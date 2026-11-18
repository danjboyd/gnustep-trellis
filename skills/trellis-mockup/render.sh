#!/bin/bash
# render.sh: lint and render a Trellis mockup the way skills/trellis-mockup
# describes. Writes PNGs and frame JSON to OUTDIR and prints what it wrote.
#
#   skills/trellis-mockup/render.sh Screen.trellis OUTDIR [--widths 340,520,900]
#                                   [--height 640] [--theme Adwaita|Gumdrop|...]
#
# Uses the Trellis install at TRELLIS_PREFIX (a scripts/trellis-update.sh
# prefix), else the tools built in this checkout.
# Every GUI run goes through scripts/run-headless.sh (private display and
# throwaway GNUSTEP_HOME); on macOS the tools run directly.
# Exit status: 0 clean, 1 lint errors or a render failed, 2 bad usage.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
[ $# -ge 2 ] || { sed -n '2,13p' "$0"; exit 2; }
spec="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
out="$2"; shift 2
widths="340,520,900" height=640 theme="Adwaita"
while [ $# -gt 0 ]; do
  case "$1" in
    --widths) widths="${2:?}"; shift 2 ;;
    --height) height="${2:?}"; shift 2 ;;
    --theme) theme="${2:?}"; shift 2 ;;
    *) echo "render.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -f "$spec" ] || { echo "render.sh: no such file: $spec" >&2; exit 2; }
mkdir -p "$out"
out="$(cd "$out" && pwd)"
name="$(basename "$spec" .trellis)"

if [ -n "${TRELLIS_PREFIX:-}" ]; then      # installed by scripts/trellis-update.sh
  bin="$TRELLIS_PREFIX/current/Tools" lib="$TRELLIS_PREFIX/current/Library/Libraries"
  preview="$TRELLIS_PREFIX/current/Applications/TrellisPreview.app/TrellisPreview"
else                                        # a built checkout
  bin="$repo/obj" lib="$repo/obj" preview="$repo/TrellisPreview.app/TrellisPreview"
fi
render="$bin/trellis-render" lint="$bin/trellis-lint"
for t in "$render" "$lint"; do [ -x "$t" ] || { echo "render.sh: missing $t (build Trellis or set TRELLIS_PREFIX)" >&2; exit 2; }; done
export LD_LIBRARY_PATH="$lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [ "$(uname)" = Darwin ]; then headless=(); else headless=("$repo/scripts/run-headless.sh"); fi
status=0

echo "== lint"
owner="$(dirname "$spec")/$(sed -n 's/.*owner: *\([A-Za-z0-9_]*\).*/\1/p' "$spec" | head -1).h"
if [ -f "$owner" ]; then "$lint" "$spec" --owner "$owner" || status=1
else "$lint" "$spec" || status=1; fi

for appearance in light dark; do
  echo "== trellis-render $appearance at $widths"
  "${headless[@]}" "$render" "$spec" --widths "$widths" --height "$height" ${theme:+--theme "$theme"} \
    --appearance "$appearance" --png "$out/$name-$appearance.png" --json "$out/$name-$appearance.json" --lint \
    || status=1
done

if [ -x "$preview" ]; then
  for appearance in light dark; do
    echo "== TrellisPreview snapshot ($appearance, ${widths##*,}x$height)"
    png="$out/$name-preview-$appearance.png" json="$out/$name-preview-$appearance.json"
    rm -f -- "$png" "$json"
    if ! "${headless[@]}" "$preview" "$spec" --snapshot "$png" --export-json "$json" \
           --appearance "$appearance" --width "${widths##*,}" --height "$height" -GSTheme "${theme:-Adwaita}" \
         || [ ! -s "$json" ]; then
      # A file that doesn't load still leaves a snapshot of the error
      # window: keep it aside so the image check can't pass it.
      [ -f "$png" ] && mv -f -- "$png" "$out/$name-preview-$appearance.load-error.png"
      echo "FAIL TrellisPreview didn't load $spec ($appearance)"; status=1
    fi
  done
else
  echo "== TrellisPreview not built; skipping its snapshots"
fi

echo "== check images"
for png in "$out/$name"-*.png; do
  case "$png" in *.load-error.png) continue ;; esac
  case "$png" in *dark*) ap=dark ;; *) ap=light ;; esac
  python3 -I "$repo/scripts/png-check.py" "$png" --appearance "$ap" || status=1
done

echo "== wrote"
ls -1 "$out"/"$name"-* | sed 's/^/  /'
exit $status
