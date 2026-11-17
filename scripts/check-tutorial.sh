#!/bin/bash
# Follows docs/tutorial.md literally: writes every ```<lang> file=PATH
# block into a work directory, then runs every ```sh step block in order
# (as one bash script, stopping at the first failure). GUI commands
# (trellis-render, the app itself) run under scripts/run-headless.sh, as
# the tutorial says to on a machine with no display. Passes if the smoke
# test prints GREETER OK.
#
#   scripts/check-tutorial.sh [work-dir]     (default: a new temp dir)
#
# The tutorial's step 1 runs `make install` in this checkout, which puts
# Trellis into the GNUstep Local domain of the toolchain on PATH (CI's
# throwaway one). Set TUTORIAL_UNINSTALL=1 to `make uninstall` afterwards.
set -euo pipefail

src=$(cd "$(dirname "$0")/.." && pwd)
work="${1:-$(mktemp -d)}"
mkdir -p "$work"
work=$(cd "$work" && pwd)
steps="$work/tutorial-steps.sh"

python3 -I - "$src/docs/tutorial.md" "$work" "$steps" <<'PY'
import os, re, sys
md, work, steps_path = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(md, encoding="utf-8").read().split("\n")
files, steps = {}, []
i = 0
while i < len(lines):
    m = re.match(r"^```(\S*)(.*)$", lines[i])
    if not m or not m.group(1):
        i += 1
        continue
    info = m.group(2)
    body = []
    i += 1
    while i < len(lines) and lines[i] != "```":
        body.append(lines[i])
        i += 1
    i += 1
    fm = re.search(r"\bfile=(\S+)", info)
    if fm:
        rel = fm.group(1)
        if rel.startswith("/") or ".." in rel.split("/"):
            sys.exit(f"bad file path in tutorial: {rel}")
        files[rel] = "\n".join(body) + "\n"
    elif m.group(1) == "sh" and re.search(r"\bstep\b", info):
        steps.append(body)
if not files or not steps:
    sys.exit("no files or steps found in the tutorial")
for rel, text in files.items():
    path = os.path.join(work, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
gui = re.compile(r"^((?:[A-Z_][A-Z0-9_]*=\S+\s+)*)(trellis-render\b|\./Greeter\.app/|openapp\b)")
with open(steps_path, "w", encoding="utf-8") as out:
    out.write("set -euo pipefail\nset -x\n")
    for n, block in enumerate(steps, 1):
        out.write(f"\n# --- step block {n}\n")
        for line in block:
            out.write(gui.sub(lambda g: g.group(1) + '"$HEADLESS" ' + g.group(2), line) + "\n")
print(f"tutorial: {len(files)} files, {len(steps)} step blocks -> {work}")
PY

cd "$work"
export TRELLIS_SRC="$src"
export HEADLESS="$src/scripts/run-headless.sh"
status=0
set +u
bash "$steps" 2>&1 | tee "$work/tutorial.log" || status=$?
set -u
if [ "${TUTORIAL_UNINSTALL:-0}" = 1 ]; then
  (cd "$src" && set +u && . scripts/env.sh && make uninstall >/dev/null)
fi
if [ $status -ne 0 ] || ! grep -q "^GREETER OK$" "$work/tutorial.log"; then
  echo "TUTORIAL FAIL (log: $work/tutorial.log)"
  exit 1
fi
for f in Greeter/greeter-320.png Greeter/greeter-560.png Greeter/Greeter.app/Greeter; do
  [ -e "$work/$f" ] || { echo "TUTORIAL FAIL: $f is missing"; exit 1; }
done
echo "TUTORIAL OK"
