#!/bin/bash
# Each bad/*.trellis must fail trellis-lint with the message in its
# "<!-- expect: ... -->" first line.
cd "$(dirname "$0")/../.."
LINT="${LINT:-./obj/trellis-lint}"
fail=0; n=0
for f in Tests/Markup/bad/*.trellis; do
  n=$((n+1))
  want=$(sed -n '1s/.*expect: \(.*\) -->.*/\1/p' "$f")
  out=$($LINT "$f" 2>&1)
  if [ $? -eq 0 ] || ! grep -qF -- "$want" <<<"$out"; then
    echo "FAIL $f: wanted '$want', got: $out"; fail=$((fail+1))
  fi
done
echo "markup error cases: $((n-fail))/$n"
# Each good/*.trellis must lint with no errors and no warnings.
g=0; gfail=0
for f in Tests/Markup/good/*.trellis; do
  g=$((g+1))
  out=$($LINT "$f" 2>&1)
  if [ $? -ne 0 ] || grep -qE "(error|warning) \[" <<<"$out"; then
    echo "FAIL $f: wanted no findings, got: $out"; gfail=$((gfail+1))
  fi
done
echo "markup clean cases: $((g-gfail))/$g"
# Each warn/*.trellis must lint without errors but with the warning in its
# "<!-- expect: ... -->" first line.
w=0; wfail=0
for f in Tests/Markup/warn/*.trellis; do
  w=$((w+1))
  want=$(sed -n '1s/.*expect: \(.*\) -->.*/\1/p' "$f")
  out=$($LINT "$f" 2>&1)
  if [ $? -ne 0 ] || ! grep -qF -- "$want" <<<"$out"; then
    echo "FAIL $f: wanted warning '$want', got: $out"; wfail=$((wfail+1))
  fi
done
echo "markup warning cases: $((w-wfail))/$w"
[ $fail -eq 0 ] && [ $gfail -eq 0 ] && [ $wfail -eq 0 ]
