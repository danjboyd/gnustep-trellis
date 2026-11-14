#!/bin/bash
# Each bad/*.trellis must fail trellis-lint with the message in its
# "<!-- expect: ... -->" first line.
cd "$(dirname "$0")/../.."
LINT="./obj/trellis-lint"
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
[ $fail -eq 0 ]
