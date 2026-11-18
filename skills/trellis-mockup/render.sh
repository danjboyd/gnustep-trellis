#!/bin/bash
# render.sh: lint and render a Trellis mockup the way skills/trellis-mockup
# describes. Writes PNGs and frame JSON to OUTDIR and prints what it wrote.
#
#   skills/trellis-mockup/render.sh Screen.trellis OUTDIR [--widths 340,520,900]
#                                   [--height 640] [--theme Adwaita|Gumdrop|...]
#                                   [--no-preview]
#
# Linux/GNUstep only for now (macOS builds put the tools elsewhere).
# Uses the Trellis install at TRELLIS_PREFIX (a scripts/trellis-update.sh
# prefix), else the tools built in this checkout.
# OUTDIR must be new or empty, so every file checked is from this run.
# TrellisPreview is required: without it the run fails, unless
# --no-preview says to skip the app check (the run then says so).
# Every GUI run goes through scripts/run-headless.sh (private display and
# throwaway GNUSTEP_HOME).
# Exit status: 0 clean, 1 lint errors or a render failed, 2 bad usage.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
[ $# -ge 2 ] || { sed -n '2,18p' "$0"; exit 2; }
[ "$(uname)" != Darwin ] || { echo "render.sh: Linux/GNUstep only for now; on macOS run build/trellis-render directly" >&2; exit 2; }
spec="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
out="$2"; shift 2
widths="340,520,900" height=640 theme="Adwaita" noPreview=0
while [ $# -gt 0 ]; do
  case "$1" in
    --widths) widths="${2:?}"; shift 2 ;;
    --height) height="${2:?}"; shift 2 ;;
    --theme) theme="${2:?}"; shift 2 ;;
    --no-preview) noPreview=1; shift ;;
    *) echo "render.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -f "$spec" ] || { echo "render.sh: no such file: $spec" >&2; exit 2; }
# The theme must be installed where the headless run will look: the
# private GNUstep home, or the toolchain's Local/System/Network library.
# Without it GNUstep silently falls back to its default grey theme.
themeDirs="$(set +eu; . "$repo/scripts/env.sh" >/dev/null 2>&1
  echo "${TRELLIS_GNUSTEP_HOME:-$HOME/.cache/trellis-gnustep-home}/GNUstep/Library/Themes"
  for v in LOCAL SYSTEM NETWORK; do echo "$(gnustep-config --variable=GNUSTEP_${v}_LIBRARY 2>/dev/null)/Themes"; done)"
found=""
while IFS= read -r d; do [ -d "$d/$theme.theme" ] && { found="$d"; break; }; done <<< "$themeDirs"
if [ -z "$found" ]; then
  echo "render.sh: the $theme theme isn't installed; GNUstep would fall back to its default theme. Looked in:" >&2
  sed 's/^/  /' <<< "$themeDirs" >&2
  echo "Copy an existing $theme.theme into the first folder (your private GNUstep home), or pass --theme. See SKILL.md, Setup." >&2
  exit 2
fi
if [ -e "$out" ] && [ -n "$(ls -A "$out" 2>/dev/null)" ]; then
  echo "render.sh: $out is not empty; use a new or empty directory so only this run's files are checked" >&2; exit 2
fi
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

headless=("$repo/scripts/run-headless.sh")
status=0
expected=()

echo "== lint"
owner="$(dirname "$spec")/$(sed -n 's/.*owner: *\([A-Za-z0-9_]*\).*/\1/p' "$spec" | head -1).h"
if [ -f "$owner" ]; then "$lint" "$spec" --owner "$owner" || status=1
else "$lint" "$spec" || status=1; fi

for appearance in light dark; do
  echo "== trellis-render $appearance at $widths"
  "${headless[@]}" "$render" "$spec" --widths "$widths" --height "$height" ${theme:+--theme "$theme"} \
    --appearance "$appearance" --png "$out/$name-$appearance.png" --json "$out/$name-$appearance.json" --lint \
    || status=1
  # trellis-render adds a -WIDTH suffix only when it renders several widths.
  case "$widths" in
    *,*) for w in ${widths//,/ }; do
           expected+=("$out/$name-$appearance-$w.png" "$out/$name-$appearance-$w.json")
         done ;;
    *) expected+=("$out/$name-$appearance.png" "$out/$name-$appearance.json") ;;
  esac
done

if [ "$noPreview" = 1 ]; then
  echo "== TrellisPreview skipped (--no-preview): the app check was NOT done"
elif [ -x "$preview" ]; then
  for appearance in light dark; do
    echo "== TrellisPreview snapshot ($appearance, ${widths##*,}x$height)"
    png="$out/$name-preview-$appearance.png" json="$out/$name-preview-$appearance.json"
    if ! "${headless[@]}" "$preview" "$spec" --snapshot "$png" --export-json "$json" \
           --appearance "$appearance" --width "${widths##*,}" --height "$height" -GSTheme "${theme:-Adwaita}" \
         || [ ! -s "$json" ]; then
      # A file that doesn't load still leaves a snapshot of the error
      # window: keep it aside so the image check can't pass it.
      [ -f "$png" ] && mv -f -- "$png" "$out/$name-preview-$appearance.load-error.png"
      echo "FAIL TrellisPreview didn't load $spec ($appearance)"; status=1
    else
      expected+=("$png" "$json")
    fi
  done
else
  echo "FAIL TrellisPreview is missing ($preview): build it, or pass --no-preview to skip the app check"
  status=1
fi

echo "== check outputs"
for f in "${expected[@]}"; do
  [ -s "$f" ] || { echo "FAIL missing or empty: $f"; status=1; }
done

echo "== check images"
for png in "$out/$name"-*.png; do
  case "$png" in *.load-error.png) continue ;; esac
  case "$png" in *dark*) ap=dark ;; *) ap=light ;; esac
  python3 -I "$repo/scripts/png-check.py" "$png" --appearance "$ap" || status=1
done

echo "== wrote"
ls -1 "$out"/"$name"-* | sed 's/^/  /'
exit $status
