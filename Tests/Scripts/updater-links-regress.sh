#!/bin/bash
# Scratch regressions for the second updater review: managed link targets
# and literal prefixes in the generated env.sh. SRC is a verified prefix
# holding v0.8.0 and v0.9.0 (from the first regression run).
set -u
UPD="$1" SRC="$2" RUN="$3"
mkdir -p "$RUN"
source "$UPD/scripts/env.sh" >/dev/null
U="$UPD/scripts/trellis-update.sh"; REPO="$UPD"
pass=0 fail=0
ok()  { echo "PASS $*"; pass=$((pass+1)); }
bad() { echo "FAIL $*"; fail=$((fail+1)); }
fresh() { rm -rf -- "${RUN:?}/$1"; cp -a "$SRC" "$RUN/$1"; echo "$RUN/$1"; }
cur() { readlink "$1/current"; }

echo "## 1. current/previous must be exactly versions/vX.Y.Z inside the prefix"
OUT="$RUN/outside"; rm -rf -- "${OUT:?}"; mkdir -p "$OUT"; cp -a "$SRC/versions/v0.9.0" "$OUT/v0.9.0"; cp -a "$SRC/versions/v0.8.0" "$OUT/v0.8.0"
X=$(fresh abs-current); ln -sfn "$OUT/v0.9.0" "$X/current"
"$U" --prefix "$X" --status >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "current: *INVALID: current points at '$OUT/v0.9.0'" "$RUN/o" && ok "status: current -> an outside tree named v0.9.0 is INVALID (rc $rc)" || { bad "abs current status rc=$rc"; cat "$RUN/o"; }
"$U" --prefix "$X" --repo "$REPO" --tag v0.9.0 >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "not a managed versions/vX.Y.Z" "$RUN/o" && [ "$(cur "$X")" = "$OUT/v0.9.0" ] && ok "update refuses and leaves the link alone: $(tail -1 "$RUN/o")" || { bad "abs current update rc=$rc"; tail -2 "$RUN/o"; }
"$U" --prefix "$X" --rollback >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "not a managed" "$RUN/o" && ok "rollback refuses too: $(tail -1 "$RUN/o")" || bad "abs current rollback rc=$rc"
X=$(fresh dotdot-current); ln -sfn "versions/../../outside/v0.9.0" "$X/current"
"$U" --prefix "$X" --repo "$REPO" --tag v0.9.0 --dry-run >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "not a managed" "$RUN/o" && ok "current -> versions/../../outside/v0.9.0 refused: $(tail -1 "$RUN/o")" || { bad "dotdot rc=$rc"; tail -2 "$RUN/o"; }
X=$(fresh abs-previous); ln -sfn "$OUT/v0.8.0" "$X/previous"
"$U" --prefix "$X" --rollback >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "previous points at '$OUT/v0.8.0'" "$RUN/o" && [ "$(cur "$X")" = versions/v0.9.0 ] && ok "rollback to previous -> outside v0.8.0 refused, current unchanged: $(tail -1 "$RUN/o")" || { bad "abs previous rc=$rc"; tail -2 "$RUN/o"; }
X=$(fresh bad-name); ln -sfn "versions/v0.8.0-evil" "$X/previous"
"$U" --prefix "$X" --rollback >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "not a managed" "$RUN/o" && ok "previous -> versions/v0.8.0-evil refused" || bad "bad name rc=$rc"
X=$(fresh not-link); rm -f -- "${X:?}/previous"; mkdir "$X/previous"
"$U" --prefix "$X" --rollback >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "previous in .* is not a symlink" "$RUN/o" && ok "previous as a plain directory refused" || { bad "not link rc=$rc"; tail -2 "$RUN/o"; }

echo "## 2. managed version directories are real directories inside the prefix"
X=$(fresh linked-version); rm -rf -- "${X:?}/versions/v0.8.0"; ln -s "$OUT/v0.8.0" "$X/versions/v0.8.0"
"$U" --prefix "$X" --rollback >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "versions/v0.8.0, which is not a real directory" "$RUN/o" && [ "$(cur "$X")" = versions/v0.9.0 ] && ok "versions/v0.8.0 as a symlink to an outside copy refused for rollback: $(tail -1 "$RUN/o")" || { bad "linked version rollback rc=$rc"; tail -2 "$RUN/o"; }
rm -f -- "${X:?}/previous"
"$U" --prefix "$X" --repo "$REPO" --tag v0.8.0 >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "not a real directory inside" "$RUN/o" && [ "$(cur "$X")" = versions/v0.9.0 ] && ok "and refused for reuse: $(tail -1 "$RUN/o")" || { bad "linked version reuse rc=$rc"; tail -2 "$RUN/o"; }
X=$(fresh linked-versions); mv "$X/versions" "$RUN/linked-versions-real"; rm -rf -- "${RUN:?}/lv-target"; mv "$RUN/linked-versions-real" "$RUN/lv-target"; ln -s "$RUN/lv-target" "$X/versions"
"$U" --prefix "$X" --status >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "INVALID" "$RUN/o" && ok "versions/ itself a symlink: status INVALID (rc $rc)" || { bad "linked versions dir rc=$rc"; cat "$RUN/o"; }
"$U" --prefix "$X" --rollback >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "not a real directory" "$RUN/o" && ok "and rollback refused: $(tail -1 "$RUN/o")" || bad "linked versions rollback rc=$rc"
X=$(fresh good); "$U" --prefix "$X" --status >"$RUN/o" 2>&1; rc=$?
[ $rc = 0 ] && [ "$(grep -c '^verified' "$RUN/o")" = 2 ] && ok "a clean copy still verifies (rc 0, 2 verified)" || { bad "clean status rc=$rc"; cat "$RUN/o"; }
"$U" --prefix "$X" --rollback >"$RUN/o" 2>&1 && "$U" --prefix "$X" --rollback >>"$RUN/o" 2>&1 && [ "$(cur "$X")" = versions/v0.9.0 ] && ok "and rolls back and forward" || bad "clean rollback"

echo "## 3. env.sh keeps a prefix with shell metacharacters literal"
WEIRD="$RUN/odd \$(touch PWNED) \`touch PWNED2\` 'q\" ;x"
rm -rf -- "$WEIRD"; cp -a "$SRC" "$WEIRD"; rm -f -- "$WEIRD/env.sh"
( cd "$RUN" && rm -f PWNED PWNED2 )
"$U" --prefix "$WEIRD" --rollback >"$RUN/o" 2>&1; rc=$?
[ $rc = 0 ] && [ -f "$WEIRD/env.sh" ] && ok "rollback in the odd prefix wrote env.sh: $(tail -1 "$RUN/o")" || { bad "odd prefix rc=$rc"; tail -3 "$RUN/o"; }
for sh in bash sh; do
  got=$(cd "$RUN" && env -i PATH=/usr/bin:/bin "$sh" -c '. "$1"; printf "%s\n%s\n" "$PATH" "$LD_LIBRARY_PATH"' x "$WEIRD/env.sh" 2>&1)
  p1=$(printf '%s\n' "$got" | sed -n 1p); l1=$(printf '%s\n' "$got" | sed -n 2p)
  [ "$p1" = "$WEIRD/current/Tools:/usr/bin:/bin" ] && [ "$l1" = "$WEIRD/current/Library/Libraries" ] \
    && [ ! -e "$RUN/PWNED" ] && [ ! -e "$RUN/PWNED2" ] && ok "$sh: PATH and LD_LIBRARY_PATH are the literal prefix; nothing ran" \
    || { bad "$sh env: PATH=$p1 LD=$l1 pwned=$(ls "$RUN" | grep -c PWNED)"; }
done
got=$(cd "$RUN" && env -i PATH=/usr/bin:/bin LD_LIBRARY_PATH=/opt/x bash -c '. "$1"; printf "%s\n" "$LD_LIBRARY_PATH"' x "$WEIRD/env.sh")
[ "$got" = "$WEIRD/current/Library/Libraries:/opt/x" ] && ok "an existing LD_LIBRARY_PATH is kept after the prefix" || bad "LD append: $got"
(cd "$RUN" && env -i PATH=/usr/bin:/bin bash -c '. "$1"; command -v trellis-lint' x "$WEIRD/env.sh") >"$RUN/o" 2>&1
[ "$(cat "$RUN/o")" = "$WEIRD/current/Tools/trellis-lint" ] && ok "trellis-lint resolves inside the odd prefix" || bad "lint path: $(cat "$RUN/o")"
echo "env.sh as written:"; sed 's/^/     /' "$WEIRD/env.sh"
echo "== $pass passed, $fail failed"
