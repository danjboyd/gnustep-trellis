#!/bin/bash
# Scratch regressions for the lead's review of the updater and render.sh.
set -u
UPD="$1" SKILL="$2" RUN="$3"
mkdir -p "$RUN"
source "$UPD/scripts/env.sh" >/dev/null
U="$UPD/scripts/trellis-update.sh"; REPO="$UPD"
pass=0 fail=0
ok()  { echo "PASS $*"; pass=$((pass+1)); }
bad() { echo "FAIL $*"; fail=$((fail+1)); }
tree() { find "$1" -printf '%P %y %s %T@\n' 2>/dev/null | sort; }
C080=$(git -C "$REPO" rev-parse 'v0.8.0^{commit}') C090=$(git -C "$REPO" rev-parse 'v0.9.0^{commit}')

echo "## 1. --dry-run and --status are read-only"
X="$RUN/not-there"
"$U" --prefix "$X" --repo "$REPO" --dry-run >"$RUN/o" 2>&1; rc=$?
[ $rc = 0 ] && [ ! -e "$X" ] && ok "dry-run on a missing prefix doesn't create it: $(tail -1 "$RUN/o")" || bad "dry-run missing prefix rc=$rc exists=$([ -e "$X" ] && echo y)"
"$U" --prefix "$X" --status >"$RUN/o" 2>&1; [ ! -e "$X" ] && ok "status on a missing prefix doesn't create it" || bad "status created $X"
E="$RUN/empty"; mkdir -p "$E"
"$U" --prefix "$E" --repo "$REPO" --dry-run >/dev/null 2>&1; "$U" --prefix "$E" --status >/dev/null 2>&1
[ -z "$(ls -A "$E")" ] && ok "dry-run and status leave an empty prefix empty (no marker, lock or .build)" || bad "empty prefix now has: $(ls -A "$E")"

echo "## 2. exact tag and commit"
P1="$RUN/prefix"
"$U" --prefix "$P1" --repo "$REPO" --tag v0.8.0 --commit "$C090" >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && [ -z "$(ls -A "$P1" 2>/dev/null | grep -v '^\.trellis-update')" ] && ok "wrong --commit refused, nothing installed: $(tail -1 "$RUN/o")" || bad "wrong commit rc=$rc"
"$U" --prefix "$P1" --repo "$REPO" --commit "$C080" >"$RUN/o" 2>&1; [ $? != 0 ] && ok "--commit without --tag refused" || bad "--commit without --tag accepted"
"$U" --prefix "$P1" --repo "$REPO" --tag v0.8.0 --commit "$C080" >"$RUN/o" 2>&1; rc=$?
[ $rc = 0 ] && ok "v0.8.0 at its exact commit installed: $(grep 'current is' "$RUN/o")" || { bad "install v0.8.0 rc=$rc"; tail -5 "$RUN/o"; }
"$U" --prefix "$P1" --repo "$REPO" --tag v0.9.0 --commit "$C090" >"$RUN/o" 2>&1; rc=$?
[ $rc = 0 ] && ok "v0.9.0 installed: $(grep 'current is' "$RUN/o")" || { bad "install v0.9.0 rc=$rc"; tail -5 "$RUN/o"; }
"$U" --prefix "$P1" --status | sed 's/^/     /'
[ -z "$(ls -d "$P1"/.build.* 2>/dev/null)" ] && ok "no .build scratch left after the runs" || bad "scratch left: $(ls -d "$P1"/.build.*)"

echo "## 3. dry-run on a populated prefix changes nothing"
tree "$P1" > "$RUN/t1"
"$U" --prefix "$P1" --repo "$REPO" --dry-run >"$RUN/o" 2>&1; "$U" --prefix "$P1" --rollback --dry-run >>"$RUN/o" 2>&1; "$U" --prefix "$P1" --status >/dev/null
tree "$P1" > "$RUN/t2"
cmp -s "$RUN/t1" "$RUN/t2" && grep -q "would roll back v0.9.0 -> v0.8.0" "$RUN/o" && ok "tree identical after dry-run, rollback dry-run and status: $(tail -1 "$RUN/o")" || { bad "tree changed"; diff "$RUN/t1" "$RUN/t2" | head; }

echo "## 4. reuse and rollback verify the install"
V8="$P1/versions/v0.8.0"
cp -p "$V8/Tools/trellis-lint" "$RUN/lint.orig"
printf 'x' >> "$V8/Tools/trellis-lint"
"$U" --prefix "$P1" --rollback >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "won't roll back to v0.8.0: .*MANIFEST" "$RUN/o" && [ "$(basename "$(readlink "$P1/current")")" = v0.9.0 ] && ok "rollback to a changed v0.8.0 refused, current still v0.9.0: $(tail -1 "$RUN/o")" || bad "tampered rollback rc=$rc"
"$U" --prefix "$P1" --repo "$REPO" --tag v0.8.0 >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "doesn't match its MANIFEST" "$RUN/o" && [ "$(basename "$(readlink "$P1/current")")" = v0.9.0 ] && ok "reuse of a changed v0.8.0 refused: $(tail -1 "$RUN/o")" || bad "tampered reuse rc=$rc"
cp -p "$RUN/lint.orig" "$V8/Tools/trellis-lint"
echo extra > "$V8/Tools/extra-file"
"$U" --prefix "$P1" --rollback >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "files not in its manifest" "$RUN/o" && ok "an extra file in v0.8.0 is refused: $(tail -1 "$RUN/o")" || bad "extra file rc=$rc"
rm -f -- "${V8:?}/Tools/extra-file"
cp -p "$V8/TRELLIS_VERSION" "$RUN/ver.orig"
printf 'v0.8.0 %s\n' "$C090" > "$V8/TRELLIS_VERSION"
"$U" --prefix "$P1" --repo "$REPO" --tag v0.8.0 >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "is commit $C090, not $C080" "$RUN/o" && ok "a v0.8.0 recording another commit is refused: $(tail -1 "$RUN/o")" || bad "wrong record rc=$rc"
cp -p "$RUN/ver.orig" "$V8/TRELLIS_VERSION"
"$U" --prefix "$P1" --rollback --commit "$C090" >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "is commit $C080, not $C090" "$RUN/o" && ok "rollback --commit with the wrong commit refused: $(tail -1 "$RUN/o")" || bad "rollback wrong commit rc=$rc"
"$U" --prefix "$P1" --rollback --commit "$C080" >"$RUN/o" 2>&1; rc=$?
[ $rc = 0 ] && ok "restored v0.8.0 verifies; rollback works: $(tail -1 "$RUN/o")" || { bad "rollback after restore rc=$rc"; cat "$RUN/o"; }
"$U" --prefix "$P1" --rollback >"$RUN/o" 2>&1 && ok "roll forward: $(tail -1 "$RUN/o")" || bad "roll forward"
L="$RUN/legacy"; mkdir -p "$L/versions"; echo "Trellis install prefix managed by scripts/trellis-update.sh" > "$L/.trellis-update-prefix"
cp -a "$P1/versions/v0.9.0" "$L/versions/"; rm -f -- "${L:?}/versions/v0.9.0/MANIFEST.sha256"
"$U" --prefix "$L" --repo "$REPO" --tag v0.9.0 >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && [ ! -e "$L/current" ] && ok "a v0.9.0 without a manifest isn't reused: $(tail -1 "$RUN/o")" || bad "legacy reuse rc=$rc"

echo "## 5. per-prefix lock and per-run scratch"
mkdir -p "$P1/.build.abc123"; touch "$P1/.current.999"
flock "$P1/.trellis-update.lock" sleep 8 & holder=$!
sleep 1
"$U" --prefix "$P1" --rollback >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "another trellis-update run" "$RUN/o" && ok "rollback refused while another run holds the lock: $(tail -1 "$RUN/o")" || bad "lock rc=$rc"
"$U" --prefix "$P1" --repo "$REPO" --tag v0.9.0 >"$RUN/o" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "another trellis-update run" "$RUN/o" && ok "update refused while locked: $(tail -1 "$RUN/o")" || bad "update under lock rc=$rc"
[ -d "$P1/.build.abc123" ] && ok "a locked-out run doesn't remove another run's scratch" || bad "scratch removed under someone else's lock"
"$U" --prefix "$P1" --status >/dev/null 2>&1 && ok "status still works while locked" || bad "status under lock"
wait "$holder"
"$U" --prefix "$P1" --repo "$REPO" --tag v0.9.0 >"$RUN/o" 2>&1; rc=$?
[ $rc = 0 ] && [ ! -e "$P1/.build.abc123" ] && [ ! -e "$P1/.current.999" ] && ok "after the lock is free: a stale run's scratch and temp link are cleaned: $(tail -1 "$RUN/o")" || bad "cleanup rc=$rc"

echo "## 6. render.sh"
R="$SKILL/skills/trellis-mockup/render.sh"; M="$SKILL/skills/trellis-mockup/example/QueueMockup.trellis"
TRELLIS_PREFIX="$P1" "$R" "$M" "$RUN/r-good" --widths 340,900 >"$RUN/r1" 2>&1; rc=$?
[ $rc = 0 ] && ok "good mockup, installed copy: rc 0, $(ls "$RUN/r-good" | wc -l) files" || { bad "good rc=$rc"; grep FAIL "$RUN/r1"; }
TRELLIS_PREFIX="$P1" "$R" "$M" "$RUN/r-good" --widths 340,900 >"$RUN/r2" 2>&1; rc=$?
[ $rc = 2 ] && grep -q "is not empty" "$RUN/r2" && ok "rerun into the same (non-empty) directory refused: $(tail -1 "$RUN/r2")" || bad "reuse outdir rc=$rc"
TRELLIS_PREFIX="$P1" "$R" "$M" "$RUN/r-one" --widths 520 >"$RUN/r3" 2>&1; rc=$?
[ $rc = 0 ] && ok "single width: rc 0 ($(ls "$RUN/r-one" | tr '\n' ' '))" || { bad "single width rc=$rc"; grep FAIL "$RUN/r3"; }
NP="$RUN/no-preview"; mkdir -p "$NP/versions"; cp -a "$P1/versions/v0.9.0" "$NP/versions/"
rm -rf -- "${NP:?}/versions/v0.9.0/Applications"; ln -s versions/v0.9.0 "$NP/current"
TRELLIS_PREFIX="$NP" "$R" "$M" "$RUN/r-np" --widths 340 >"$RUN/r4" 2>&1; rc=$?
[ $rc = 1 ] && grep -q "TrellisPreview is missing" "$RUN/r4" && ok "missing TrellisPreview fails: $(grep 'FAIL Trellis' "$RUN/r4")" || bad "missing preview rc=$rc"
TRELLIS_PREFIX="$NP" "$R" "$M" "$RUN/r-np2" --widths 340 --no-preview >"$RUN/r5" 2>&1; rc=$?
[ $rc = 0 ] && grep -q "NOT done" "$RUN/r5" && ok "--no-preview passes and says so: $(grep 'NOT done' "$RUN/r5")" || bad "no-preview rc=$rc"
printf '<window title="Broken sample">\n  <column>\n    <label text="unclosed"\n</window>\n' > "$RUN/Broken.trellis"
TRELLIS_PREFIX="$P1" "$R" "$RUN/Broken.trellis" "$RUN/r-broken" --widths 340 >"$RUN/r6" 2>&1; rc=$?
[ $rc = 1 ] && ls "$RUN/r-broken" | grep -q load-error && ok "broken mockup fails; $(grep -c 'FAIL' "$RUN/r6") FAIL lines; kept: $(ls "$RUN/r-broken" | tr '\n' ' ')" || bad "broken rc=$rc"
SH="$RUN/darwin-shim"; mkdir -p "$SH"; printf '#!/bin/sh\necho Darwin\n' > "$SH/uname"; chmod +x "$SH/uname"
PATH="$SH:$PATH" TRELLIS_PREFIX="$P1" "$R" "$M" "$RUN/r-mac" >"$RUN/r7" 2>&1; rc=$?
[ $rc = 2 ] && [ ! -e "$RUN/r-mac" ] && ok "on macOS (uname shim) it stops at once: $(tail -1 "$RUN/r7")" || bad "darwin rc=$rc"
echo "== $pass passed, $fail failed"
