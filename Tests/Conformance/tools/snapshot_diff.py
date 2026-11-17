#!/usr/bin/env python3
"""Summarize what a WPT snapshot change does to the imported cases.

    python3 -I Tests/Conformance/tools/snapshot_diff.py OLD_CASES NEW_CASES [--json]

OLD_CASES and NEW_CASES are case trees (Tests/Conformance/cases/<suite>, or
an importer output directory) from two WPT commits. Case ids are positional
(file/index), so when upstream inserts a container every later case in that
file would look changed. Cases are matched by a stable identity instead: the
source file plus a hash of the case's input (root tree, direction, available
size, requires), which doesn't involve the index or the expectations. The
summary sorts every case into one of:

  unchanged        same input and expectations (the recorded commit may differ)
  renumbered       same input and expectations under another index
  revised          same input, different expectations: upstream changed what
                   the browser should produce (e.g. grid-gutters-and-flex-
                   content-001/6 and /7 at 34bdce1). The engine may need to
                   follow; check these first.
  input-changed    the file's case at this index has a different input
  added / removed  a case or file only in one tree

Exit status: 0 when nothing is revised, input-changed, added or removed
(a pure commit bump), 1 otherwise, so a refresh script can stop for review.
"""
import argparse
import collections
import glob
import hashlib
import json
import os
import sys

INPUT_KEYS = ("root", "direction", "available", "requires", "anchor", "pixelScale")


def load(tree):
    cases = {}
    for f in glob.glob(os.path.join(tree, "**", "*.json"), recursive=True):
        try:
            c = json.load(open(f))
        except ValueError:
            continue
        if isinstance(c, dict) and "id" in c and "source" in c:
            cases[c["id"]] = c
    return cases


def input_hash(c):
    key = {k: c.get(k) for k in INPUT_KEYS}
    return hashlib.sha256(json.dumps(key, sort_keys=True).encode()).hexdigest()[:16]


def file_of(c):
    return c["source"].get("file", c["id"].rsplit("/", 1)[0])


def diff(old, new):
    """Match in passes: the same id with the same input; then the same input
    under another id in the same file (renumbered); what's left is an input
    change at the same id, or an added or removed case."""
    out = collections.defaultdict(list)
    matched_old, pending = set(), []
    for cid, c in sorted(new.items()):
        o = old.get(cid)
        if o is not None and input_hash(o) == input_hash(c):
            matched_old.add(cid)
            if o.get("expected") == c.get("expected"):
                out["unchanged"].append(cid)
            else:
                out["revised"].append({"id": cid, "old": o.get("expected"), "new": c.get("expected")})
        else:
            pending.append(cid)
    by_key = collections.defaultdict(list)
    for oid in sorted(set(old) - matched_old):
        by_key[(file_of(old[oid]), input_hash(old[oid]))].append(oid)
    leftover = []
    for cid in pending:
        c = new[cid]
        cands = by_key.get((file_of(c), input_hash(c)))
        if cands:
            oid = cands.pop(0)
            matched_old.add(oid)
            entry = {"id": cid, "was": oid}
            if old[oid].get("expected") == c.get("expected"):
                out["renumbered"].append(entry)
            else:
                entry.update(old=old[oid].get("expected"), new=c.get("expected"))
                out["revised"].append(entry)
        else:
            leftover.append(cid)
    for cid in leftover:
        if cid in old and cid not in matched_old:
            matched_old.add(cid)
            out["input-changed"].append(cid)
        else:
            out["added"].append(cid)
    out["removed"] = sorted(set(old) - matched_old)
    return out


def leaf_changes(a, b, path="root"):
    """Expected values that differ, as 'path.key: old -> new'."""
    a, b = a or {}, b or {}
    ch = []
    for k in sorted(set(a) | set(b)):
        if k == "children":
            ka, kb = a.get(k) or [], b.get(k) or []
            for i in range(max(len(ka), len(kb))):
                ch += leaf_changes(ka[i] if i < len(ka) else None,
                                   kb[i] if i < len(kb) else None, f"{path}/{i}")
        elif a.get(k) != b.get(k):
            ch.append(f"{path}.{k}: {a.get(k)} -> {b.get(k)}")
    return ch


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old")
    ap.add_argument("new")
    ap.add_argument("--json", action="store_true", help="machine-readable summary")
    a = ap.parse_args()
    old, new = load(a.old), load(a.new)
    d = diff(old, new)
    commits = sorted({c["source"].get("commit", "?")[:12] for c in old.values()}), \
        sorted({c["source"].get("commit", "?")[:12] for c in new.values()})
    if a.json:
        json.dump({"commits": {"old": commits[0], "new": commits[1]},
                   **{k: d[k] for k in ("unchanged", "renumbered", "revised", "input-changed",
                                        "added", "removed")}},
                  sys.stdout, indent=1, sort_keys=True)
        print()
    else:
        print(f"WPT {','.join(commits[0])} -> {','.join(commits[1])}: "
              f"{len(old)} -> {len(new)} cases")
        for k in ("unchanged", "renumbered", "revised", "input-changed", "added", "removed"):
            print(f"  {k:14} {len(d[k])}")
        for r in d["revised"]:
            print(f"revised {r['id']}" + (f" (was {r['was']})" if "was" in r else ""))
            for line in leaf_changes(r["old"], r["new"]):
                print("    " + line)
        for k in ("input-changed", "added", "removed"):
            files = collections.Counter(x.rsplit("/", 1)[0] for x in d[k])
            for f, n in sorted(files.items()):
                print(f"{k} {f}: {n} case(s)")
    review = any(d[k] for k in ("revised", "input-changed", "added", "removed"))
    return 1 if review else 0


if __name__ == "__main__":
    sys.exit(main())
