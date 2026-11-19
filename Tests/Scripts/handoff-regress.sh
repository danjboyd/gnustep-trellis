#!/bin/bash
# skills/trellis-mockup/handoff.py: the sample turns into one-line
# commands that recreate it, and mockups that can't go this way are
# refused with exit 3. Prints HANDOFF OK.
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
H="$REPO/skills/trellis-mockup/handoff.py"
EX="$REPO/skills/trellis-mockup/example"
WORK=$(TMPDIR=/tmp mktemp -d /tmp/hand.XXXXXX)
trap 'rm -rf -- "${WORK:?}"' EXIT
pass=0 fail=0
ok()  { echo "ok   $*"; pass=$((pass+1)); }
bad() { echo "FAIL $*"; fail=$((fail+1)); }

# The sample: commands are one line, at most 2000 characters, at most 8,
# the last one opens TrellisPreview, and they recreate both files.
if python3 -I "$H" "$EX/QueueMockup.trellis" --json "$WORK/c.json" > "$WORK/c.txt" 2> "$WORK/err"; then
  n=$(wc -l < "$WORK/c.txt"); long=$(awk 'length > 2000' "$WORK/c.txt" | wc -l)
  [ "$n" -ge 2 ] && [ "$n" -le 8 ] && [ "$long" -eq 0 ] && ok "sample: $n one-line commands, none over 2000" || bad "sample: $n commands, $long too long"
  tail -1 "$WORK/c.txt" | grep -q 'TrellisPreview "$D/QueueMockup.trellis" &$' && ok "last command opens TrellisPreview" || bad "last command"
  mkdir "$WORK/home"; head -n -1 "$WORK/c.txt" | HOME="$WORK/home" bash
  D="$WORK/home/agent-shared/trellis-mockups/QueueMockup"
  cmp -s "$EX/QueueMockup.trellis" "$D/QueueMockup.trellis" && cmp -s "$EX/QueueMockup.sample.json" "$D/QueueMockup.sample.json" \
    && ok "commands recreate both files byte for byte" || bad "files differ"
  python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); assert all("\n" not in x["text"] for x in c)' "$WORK/c.json" \
    && ok "--json writes the ask's command list" || bad "--json"
else
  bad "sample refused: $(cat "$WORK/err")"
fi

printf "<column><label>It's here</label></column>\n" > "$WORK/Quote.trellis"
python3 -I "$H" "$WORK/Quote.trellis" > /dev/null 2>&1; [ $? -eq 3 ] && ok "refused: a single quote" || bad "single quote not refused"
printf '<column>\t<label>Tab</label></column>\n' > "$WORK/Tab.trellis"
python3 -I "$H" "$WORK/Tab.trellis" > /dev/null 2>&1; [ $? -eq 3 ] && ok "refused: a tab" || bad "tab not refused"
printf '<column><label>No newline</label></column>' > "$WORK/NoNl.trellis"
python3 -I "$H" "$WORK/NoNl.trellis" > /dev/null 2>&1; [ $? -eq 3 ] && ok "refused: no final newline" || bad "missing newline not refused"
python3 -I - "$WORK/Big.trellis" <<'EOF'
import sys
with open(sys.argv[1], "w") as f:
    f.write("<column>\n")
    for i in range(600):
        f.write('  <label id="row%d">Sample item number %d with some filler text</label>\n' % (i, i))
    f.write("</column>\n")
EOF
python3 -I "$H" "$WORK/Big.trellis" > /dev/null 2> "$WORK/big.err"; rc=$?
[ $rc -eq 3 ] && grep -q "PNGs only" "$WORK/big.err" && ok "refused: too big for 8 commands" || bad "big mockup: rc=$rc"
printf '<column/>\n' > "$WORK/bad name.trellis"
python3 -I "$H" "$WORK/bad name.trellis" > /dev/null 2>&1; [ $? -eq 2 ] && ok "refused: a name with a space" || bad "bad name not refused"

echo "== $pass passed, $fail failed"
[ $fail -eq 0 ] && echo "HANDOFF OK"
exit $fail
