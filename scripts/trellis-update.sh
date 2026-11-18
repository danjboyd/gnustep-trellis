#!/bin/bash
# trellis-update.sh: install the newest stable Trellis tag into a prefix,
# with rollback. DRAFT: Linux/GNUstep only; macOS and Windows are not done.
#
#   scripts/trellis-update.sh --prefix DIR [--repo URL|PATH] [--tag vX.Y.Z]
#                             [--commit SHA] [--keep N] [--skip-checks] [--dry-run]
#   scripts/trellis-update.sh --prefix DIR --rollback [--dry-run]
#   scripts/trellis-update.sh --prefix DIR --status
#
# Stable tags are annotated vMAJOR.MINOR.PATCH tags: Trellis only makes
# those once CI on main and the macOS conformance gate have passed at the
# commit. Lightweight tags and anything else are ignored. --commit SHA
# pins the install: the tag must resolve to exactly that commit (use it
# with --tag for an approved install).
#
# Layout under DIR:
#   versions/vX.Y.Z/   Library/Libraries, Library/Headers, Tools, Applications,
#                      TRELLIS_VERSION ("tag commit") and MANIFEST.sha256
#   current            symlink to the version in use (switched atomically)
#   previous           symlink to the one before (what --rollback returns to)
#   env.sh             source it: PATH and LD_LIBRARY_PATH for current
#   .build.XXXXXX/     this run's scratch clone and staging, removed after
#   .trellis-update.lock   held while an update or rollback runs
#   .trellis-update-prefix marker: the script refuses any other non-empty DIR
#
# --status and --dry-run write nothing anywhere under DIR (or create it).
# A version is switched to only after it builds and its `make check`
# passes (engine and conformance), unless --skip-checks. An installed
# version is reused, rolled back to or kept current only if its
# TRELLIS_VERSION is exactly the expected tag and commit and every file
# still matches its MANIFEST.sha256; otherwise the run fails and current
# is unchanged. The previous version is kept, and the --keep newest
# others (default 2); older ones are removed. current and previous are
# never removed.
#
# Needs the GNUstep toolchain on PATH (source scripts/env.sh or
# GNUstep.sh first). Nothing outside DIR is written, except a temporary
# tag listing for --dry-run (in $TMPDIR, removed after).

set -euo pipefail

prefix="" repo="https://github.com/danjboyd/gnustep-trellis.git" tag="" wantCommit=""
keep=2 rollback=0 status=0 skipChecks=0 dryRun=0

die() { echo "trellis-update: $*" >&2; exit 1; }
say() { echo "trellis-update: $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) prefix="${2:?--prefix needs a directory}"; shift 2 ;;
    --repo) repo="${2:?--repo needs a URL or path}"; shift 2 ;;
    --tag) tag="${2:?--tag needs a tag}"; shift 2 ;;
    --commit) wantCommit="${2:?--commit needs a commit id}"; shift 2 ;;
    --keep) keep="${2:?--keep needs a number}"; shift 2 ;;
    --rollback) rollback=1; shift ;;
    --status) status=1; shift ;;
    --skip-checks) skipChecks=1; shift ;;
    --dry-run) dryRun=1; shift ;;
    -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done
[ -n "$prefix" ] || die "--prefix is required"
case "$keep" in ''|*[!0-9]*) die "--keep takes a number" ;; esac
case "$wantCommit" in
  '') ;;
  *[!0-9a-f]*) die "--commit takes a full 40-character commit id" ;;
  *) [ ${#wantCommit} = 40 ] || die "--commit takes a full 40-character commit id" ;;
esac
[ -z "$wantCommit" ] || [ -n "$tag" ] || [ "$rollback" = 1 ] || die "--commit needs --tag"
readOnly=0
if [ "$status" = 1 ] || [ "$dryRun" = 1 ]; then readOnly=1; fi

# Resolve the prefix without creating it in the read-only modes.
if [ -d "$prefix" ]; then
  prefix="$(cd "$prefix" && pwd -P)"
elif [ -e "$prefix" ]; then
  die "$prefix exists and is not a directory"
elif [ "$readOnly" = 1 ]; then
  parent="$(cd "$(dirname "$prefix")" 2>/dev/null && pwd -P)" || die "$(dirname "$prefix") doesn't exist"
  prefix="$parent/$(basename "$prefix")"
  if [ "$status" = 1 ]; then echo "prefix:   $prefix (not created yet)"; exit 0; fi
  [ "$rollback" = 0 ] || die "nothing to roll back to ($prefix doesn't exist)"
else
  mkdir -p "$prefix"
  prefix="$(cd "$prefix" && pwd -P)"
fi
[ "$prefix" != "/" ] || die "refusing to use / as the prefix"
# Only an empty directory, or one this script set up (it holds the marker),
# is a prefix: never a toolchain, a home directory or anything else.
marker="$prefix/.trellis-update-prefix"
if [ -d "$prefix" ] && [ ! -e "$marker" ]; then
  [ -z "$(ls -A "$prefix")" ] \
    || die "$prefix is not empty and wasn't set up by trellis-update.sh; use an empty or new directory"
  [ "$readOnly" = 1 ] || echo "Trellis install prefix managed by scripts/trellis-update.sh" > "$marker"
fi

versionOf() {   # the version a symlink in the prefix points at, or nothing
  local l="$prefix/$1"
  if [ -L "$l" ]; then basename "$(readlink "$l")"; fi
}

# verifyVersion TAG [COMMIT]: versions/TAG is a complete install of exactly
# TAG (at COMMIT when given) whose files all match its manifest. Prints
# the recorded commit, or (failing) why not.
verifyVersion() {
  local t="$1" c="${2:-}" d="$prefix/versions/$1" rec f
  [ -d "$d" ] || { echo "versions/$t is missing"; return 1; }
  [ -f "$d/TRELLIS_VERSION" ] || { echo "versions/$t has no TRELLIS_VERSION"; return 1; }
  rec="$(cat "$d/TRELLIS_VERSION")"
  case "$rec" in
    "$t "*) ;;
    *) echo "versions/$t records '$rec', not $t"; return 1 ;;
  esac
  local rc="${rec#"$t "}"
  case "$rc" in *[!0-9a-f]*|'') echo "versions/$t records a bad commit '$rc'"; return 1 ;; esac
  [ ${#rc} = 40 ] || { echo "versions/$t records a bad commit '$rc'"; return 1; }
  if [ -n "$c" ] && [ "$rc" != "$c" ]; then
    echo "versions/$t is commit $rc, not $c"; return 1
  fi
  for f in Tools/trellis-lint Tools/trellis-render Applications/TrellisPreview.app/TrellisPreview \
           Library/Libraries/libTrellis.so Library/Libraries/libTrellisEngine.so; do
    [ -e "$d/$f" ] || { echo "versions/$t is missing $f"; return 1; }
  done
  [ -s "$d/MANIFEST.sha256" ] || { echo "versions/$t has no MANIFEST.sha256"; return 1; }
  (cd "$d" && sha256sum --quiet --strict -c MANIFEST.sha256 >/dev/null 2>&1) \
    || { echo "versions/$t doesn't match its MANIFEST.sha256 (files changed or missing)"; return 1; }
  # Nothing extra: every regular file and link is in the manifest.
  local extra
  extra="$(cd "$d" && LC_ALL=C comm -13 <(sed 's/^[0-9a-f]*  //' MANIFEST.sha256 | LC_ALL=C sort) \
           <(find . \( -type f -o -type l \) ! -name MANIFEST.sha256 | sed 's|^\./||' | LC_ALL=C sort) | head -3)"
  [ -z "$extra" ] || { echo "versions/$t has files not in its manifest: $(echo $extra)"; return 1; }
  echo "$rc"
}

if [ "$status" = 1 ]; then
  echo "prefix:   $prefix"
  echo "current:  $(versionOf current)"
  echo "previous: $(versionOf previous)"
  echo "versions: $(ls "$prefix/versions" 2>/dev/null | tr '\n' ' ')"
  for v in $(versionOf current) $(versionOf previous); do
    if why="$(verifyVersion "$v")"; then echo "verified: $v ($why)"; else echo "INVALID:  $why"; fi
  done
  exit 0
fi

lockAndClean() {   # one update or rollback at a time per prefix
  exec 9>"$prefix/.trellis-update.lock"
  flock -n 9 || die "another trellis-update run is using $prefix; try again when it finishes"
  # Under the lock no other run is active: scratch left by a killed run goes.
  local s
  for s in "$prefix"/.build.*; do
    [ -d "$s" ] || continue
    case "$(basename "$s")" in .build.??????) rm -rf -- "${s:?}" ;; esac
  done
  rm -f -- "${prefix:?}"/.current.* "${prefix:?}"/.previous.* "${prefix:?}"/.env.sh.*
}

writeEnv() {
  local tmp="$prefix/.env.sh.$$"
  cat > "$tmp" <<EOF
# Generated by trellis-update.sh. Source it to use the current Trellis.
export PATH="$prefix/current/Tools:\$PATH"
export LD_LIBRARY_PATH="$prefix/current/Library/Libraries\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
EOF
  mv -f "$tmp" "$prefix/env.sh"
}

switchTo() {    # point current at versions/$1 (atomic rename), previous at the old one
  local new="$1" old
  old="$(versionOf current)"
  ln -sfn "versions/$new" "$prefix/.current.$$"
  mv -T "$prefix/.current.$$" "$prefix/current"
  if [ -n "$old" ] && [ "$old" != "$new" ]; then
    ln -sfn "versions/$old" "$prefix/.previous.$$"
    mv -T "$prefix/.previous.$$" "$prefix/previous"
  fi
  writeEnv
  say "current is $new${old:+ (previous: $old)}"
}

if [ "$rollback" = 1 ]; then
  cur="$(versionOf current)" prev="$(versionOf previous)"
  [ -n "$prev" ] || die "nothing to roll back to (no previous version)"
  [ "$dryRun" = 1 ] || lockAndClean
  why="$(verifyVersion "$prev" "$wantCommit")" || die "won't roll back to $prev: $why; current ($cur) is unchanged"
  [ "$dryRun" = 1 ] && { say "would roll back $cur -> $prev ($why)"; exit 0; }
  switchTo "$prev"
  exit 0
fi

command -v gnustep-config >/dev/null || die "gnustep-config not on PATH: source the toolchain first"
localRoot="$(gnustep-config --variable=GNUSTEP_LOCAL_LIBRARIES)"
localRoot="${localRoot%/Library/Libraries}"
[ -n "$localRoot" ] && [ "$localRoot" != "/" ] || die "can't find GNUSTEP_LOCAL_ROOT"

# This run's scratch: a fresh directory (outside the prefix for --dry-run).
if [ "$dryRun" = 1 ]; then
  build="$(mktemp -d "${TMPDIR:-/tmp}/trellis-update.XXXXXX")"
else
  lockAndClean
  build="$(mktemp -d "$prefix/.build.XXXXXX")"
fi
cleanup() { if [ -n "${build:-}" ] && [ -d "$build" ]; then rm -rf -- "${build:?}"; fi; }
trap cleanup EXIT

# Find the newest annotated release tag (or check the one asked for).
git init -q "$build/tags"
git -C "$build/tags" fetch -q --depth 1 "$repo" "+refs/tags/*:refs/tags/*" 2>/dev/null \
  || git -C "$build/tags" fetch -q "$repo" "+refs/tags/*:refs/tags/*"
stableTags() {
  git -C "$build/tags" for-each-ref --format='%(objecttype) %(refname:strip=2)' refs/tags \
    | awk '$1 == "tag" && $2 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ { print $2 }' | sort -V
}
if [ -z "$tag" ]; then
  tag="$(stableTags | tail -1)"
  [ -n "$tag" ] || die "no annotated vX.Y.Z tags in $repo"
else
  stableTags | grep -qx -- "$tag" || die "$tag is not an annotated vX.Y.Z tag in $repo"
fi
commit="$(git -C "$build/tags" rev-parse "$tag^{commit}")"
if [ -n "$wantCommit" ] && [ "$commit" != "$wantCommit" ]; then
  die "$tag is commit $commit in $repo, not the expected $wantCommit; nothing changed"
fi
say "stable tag: $tag ($commit)"

cur="$(versionOf current)"
if [ -d "$prefix/versions/$tag" ]; then
  why="$(verifyVersion "$tag" "$commit")" \
    || die "installed $why; current${cur:+ ($cur)} is unchanged. Remove versions/$tag to reinstall it"
  if [ "$cur" = "$tag" ]; then say "$tag is already current (verified)"; exit 0; fi
fi
if [ "$dryRun" = 1 ]; then
  if [ -d "$prefix/versions/$tag" ]; then say "would switch to the installed $tag${cur:+ over $cur}"
  else say "would install $tag${cur:+ over $cur}"; fi
  exit 0
fi

if [ ! -d "$prefix/versions/$tag" ]; then
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" "$repo" "$build/src"
  [ "$(git -C "$build/src" rev-parse HEAD)" = "$commit" ] || die "clone of $tag is not at $commit"
  say "building $tag"
  make -s -C "$build/src" >"$build/make.log" 2>&1 || { tail -20 "$build/make.log" >&2; die "build of $tag failed"; }
  if [ "$skipChecks" = 0 ]; then
    say "checking $tag (make check)"
    make -s -C "$build/src" check >"$build/check.log" 2>&1 \
      || { tail -20 "$build/check.log" >&2; die "make check failed for $tag; current is unchanged"; }
    grep -E "^PASS" "$build/check.log" | sed 's/^/  /' || true
  fi
  make -s -C "$build/src" install DESTDIR="$build/stage" >"$build/install.log" 2>&1 \
    || { tail -20 "$build/install.log" >&2; die "staged install of $tag failed"; }
  [ -d "$build/stage$localRoot" ] || die "staged install has no $localRoot"
  st="$build/stage$localRoot"
  printf '%s %s\n' "$tag" "$commit" > "$st/TRELLIS_VERSION"
  # Written outside the staged tree first, so the manifest never lists itself.
  (cd "$st" && find . \( -type f -o -type l \) | sed 's|^\./||' | LC_ALL=C sort \
     | while IFS= read -r f; do sha256sum -- "$f"; done) > "$build/MANIFEST.sha256"
  mv -f "$build/MANIFEST.sha256" "$st/MANIFEST.sha256"
  mkdir -p "$prefix/versions"
  mv -T "$st" "$prefix/versions/$tag.tmp"
  mv -T "$prefix/versions/$tag.tmp" "$prefix/versions/$tag"
  why="$(verifyVersion "$tag" "$commit")" || die "fresh install of $tag fails its own check: $why"
fi

# Smoke test from the installed tree before switching.
if [ "$skipChecks" = 0 ]; then
  LD_LIBRARY_PATH="$prefix/versions/$tag/Library/Libraries${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$prefix/versions/$tag/Tools/trellis-lint" --help >/dev/null 2>&1 \
    || [ $? -le 2 ] || die "installed trellis-lint of $tag doesn't run; current is unchanged"
fi

switchTo "$tag"

# Prune: keep current, previous and the --keep newest others.
cur="$(versionOf current)" prev="$(versionOf previous)"
n=0
for v in $(ls "$prefix/versions" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -rV); do
  [ "$v" = "$cur" ] || [ "$v" = "$prev" ] && continue
  n=$((n + 1))
  if [ "$n" -gt "$keep" ]; then
    case "$v" in v[0-9]*) rm -rf -- "${prefix:?}/versions/${v:?}"; say "removed old $v" ;; esac
  fi
done
