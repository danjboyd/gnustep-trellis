#!/usr/bin/env python3
"""Check Tests/Reference/migration.expect.json: the frames that changed
between Trellis 0.5.x and 0.7 (percentage heights, logical properties under
rtl, spanning grid items over an empty intrinsic track).

    python3 -I scripts/check-migration.py [--render build/trellis-render]
    python3 -I scripts/check-migration.py --was --render /path/to/0.5.1/trellis-render

Renders the fixture window-free and compares each check's 'frame' (or its
'was' values with --was, against an older trellis-render) to the dump.
Prints MIGRATION OK or the mismatches.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile


def find(n, ident):
    if n.get("id") == ident:
        return n
    for c in n.get("children") or []:
        r = find(c, ident)
        if r is not None:
            return r
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--render", default=os.environ.get("RENDER", "build/trellis-render"))
    ap.add_argument("--expect", default="Tests/Reference/migration.expect.json")
    ap.add_argument("--was", action="store_true", help="check the 0.5.x values instead")
    a = ap.parse_args()
    exp = json.load(open(a.expect))
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "m.json")
        subprocess.run([a.render, os.path.abspath(exp["spec"]), "--width", str(exp["width"]),
                        "--height", str(exp["height"]), "--json", out], capture_output=True)
        if not os.path.exists(out):
            print("MIGRATION FAIL: render failed")
            return 1
        root = json.load(open(out))["root"]
    bad = 0
    key = "was" if a.was else "frame"
    for c in exp["checks"]:
        ident, *path = c["at"].split("/")
        n = find(root, ident)
        for i in path:
            n = (n.get("children") or [None] * (int(i) + 1))[int(i)] if n else None
        got = {k: n.get(k) for k in c[key]} if n else None
        ok = got is not None and all(abs(got[k] - v) <= 0.5 for k, v in c[key].items())
        print(f"{'ok  ' if ok else 'FAIL'} {c['at']}: {c[key]}" + ("" if ok else f" got {got}") + f"  ({c['why']})")
        bad += not ok
    print("MIGRATION " + ("OK" if not bad else f"FAIL ({bad})"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
