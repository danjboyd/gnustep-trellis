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
  input-changed    the file's case at this index has a different input (the
                   differing input paths are listed)
  moved            same input and expectations in another file (a renamed
                   or moved upstream test)
  added / removed  a case or file only in one tree. With the importer's
                   IMPORT-REPORT.tsv in both trees, a whole file that came
                   or went is explained: new or deleted upstream, or
                   skipped / no longer skipped by the importer (and why).

Exit status: 0 when nothing is revised, input-changed, moved, added or removed
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


def load_report(tree):
    """IMPORT-REPORT.tsv (written by import_wpt.py): {file: (status, detail)}."""
    out = {}
    p = os.path.join(tree, "IMPORT-REPORT.tsv")
    if not os.path.exists(p):
        return None
    for line in open(p, encoding="utf-8"):
        if line.startswith("#") or "\t" not in line:
            continue
        status, f, detail = (line.rstrip("\n").split("\t") + ["", ""])[:3]
        out[f] = (status, detail)
    return out


def input_changes(a, b, path="root", out=None, limit=3):
    """Paths where two cases' inputs differ, as 'path: old -> new'."""
    out = [] if out is None else out
    if len(out) >= limit:
        return out
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            input_changes(a.get(k), b.get(k), f"{path}.{k}", out, limit)
    elif isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        for i, (x, y) in enumerate(zip(a, b)):
            input_changes(x, y, f"{path}[{i}]", out, limit)
    elif a != b:
        out.append(f"{path}: {json.dumps(a)[:60]} -> {json.dumps(b)[:60]}")
    return out


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
    # A case with the same input and expectations in another file: the
    # upstream file was renamed or moved.
    by_content = collections.defaultdict(list)
    for oid in sorted(set(old) - matched_old):
        if oid not in new:
            by_content[(input_hash(old[oid]), json.dumps(old[oid].get("expected"), sort_keys=True))].append(oid)
    rest = []
    for cid in leftover:
        c = new[cid]
        cands = [] if cid in old else by_content.get((input_hash(c), json.dumps(c.get("expected"), sort_keys=True)))
        if cands:
            oid = cands.pop(0)
            matched_old.add(oid)
            out["moved"].append({"id": cid, "was": oid})
        else:
            rest.append(cid)
    for cid in rest:
        if cid in old and cid not in matched_old:
            matched_old.add(cid)
            out["input-changed"].append({"id": cid, "changes": input_changes(
                {k: old[cid].get(k) for k in INPUT_KEYS}, {k: new[cid].get(k) for k in INPUT_KEYS})})
        else:
            out["added"].append(cid)
    out["removed"] = sorted(set(old) - matched_old)
    return out


def explain_files(kind, ids, cases, old_report, new_report):
    """Per source file: count, and why the file came or went when the
    import reports say."""
    files = collections.Counter(file_of(cases[i]) for i in ids)
    rows = []
    for f, n in sorted(files.items()):
        why = ""
        if old_report is not None and new_report is not None:
            o, w = old_report.get(f), new_report.get(f)
            if kind == "added":
                if o is None:
                    why = "new upstream (or newly a check-layout test)"
                elif o[0] == "skipped":
                    why = "no longer skipped (was: %s)" % o[1]
            else:
                if w is None:
                    why = "gone upstream (deleted, renamed, or no longer a check-layout test)"
                elif w[0] == "skipped":
                    why = "now skipped: %s" % w[1]
        rows.append((f, n, why))
    return rows


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
    old_report, new_report = load_report(a.old), load_report(a.new)
    d = diff(old, new)
    commits = sorted({c["source"].get("commit", "?")[:12] for c in old.values()}), \
        sorted({c["source"].get("commit", "?")[:12] for c in new.values()})
    kinds = ("unchanged", "renumbered", "moved", "revised", "input-changed", "added", "removed")
    explained = {k: explain_files(k, d[k], new if k == "added" else old, old_report, new_report)
                 for k in ("added", "removed")}
    if a.json:
        json.dump({"commits": {"old": commits[0], "new": commits[1]},
                   **{k: d[k] for k in kinds},
                   "files": {k: [{"file": f, "cases": n, "why": w} for f, n, w in rows]
                             for k, rows in explained.items()}},
                  sys.stdout, indent=1, sort_keys=True)
        print()
    else:
        print(f"WPT {','.join(commits[0])} -> {','.join(commits[1])}: "
              f"{len(old)} -> {len(new)} cases")
        for k in kinds:
            print(f"  {k:14} {len(d[k])}")
        for r in d["revised"]:
            print(f"revised {r['id']}" + (f" (was {r['was']})" if "was" in r else ""))
            for line in leaf_changes(r["old"], r["new"]):
                print("    " + line)
        for r in d["moved"]:
            print(f"moved {r['was']} -> {r['id']}")
        shown = set()
        for r in d["input-changed"]:
            f = file_of(new[r["id"]])
            key = (f, tuple(c.split(":")[0] for c in r["changes"]))
            if key in shown:
                continue
            shown.add(key)
            n = sum(1 for x in d["input-changed"] if file_of(new[x["id"]]) == f)
            print(f"input-changed {f}: {n} case(s), e.g. {r['id'].rsplit('/', 1)[-1]}")
            for line in r["changes"]:
                print("    " + line)
        for k in ("added", "removed"):
            for f, n, why in explained[k]:
                print(f"{k} {f}: {n} case(s)" + (f" ({why})" if why else ""))
    review = any(d[k] for k in ("revised", "input-changed", "moved", "added", "removed"))
    return 1 if review else 0


if __name__ == "__main__":
    sys.exit(main())
