#!/usr/bin/env python3
"""Compare parity results (docs/windows.md, Tests/Parity/run.sh).

    compare.py --pixels A.png B.png
        Same platform and build: the two PNGs must be identical (exit 0),
        e.g. a TrellisPreview snapshot and trellis-render's PNG.

    compare.py LINUX_OUT WINDOWS_OUT [--tolerance PX]
        Two run.sh output folders from different platforms. Pixels aren't
        comparable there (fonts differ), so for every frames JSON both have
        (open, resize, render, reload):
          - the view tree must match: the same classes and ids, in the same
            order and nesting (FAIL otherwise);
          - the Tab order (ids) must match (FAIL otherwise);
          - every frame must be within the tolerance (default 24 px) in x,
            y, width and height (FAIL otherwise; the largest differences
            are listed);
          - lint findings that differ (rule and id) are listed as WARN:
            text that fits on one platform can clip on the other.
        Both manifests' cases must have passed. Exit 0 when nothing FAILs.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "scripts"))


def read_png(path):
    import importlib.util
    spec = importlib.util.spec_from_file_location("pngcheck", os.path.join(HERE, "..", "..", "scripts", "png-check.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.read_png(path)


def pixels(a, b):
    w1, h1, r1, p1 = read_png(a)
    w2, h2, r2, p2 = read_png(b)
    if (w1, h1) != (w2, h2):
        print("FAIL sizes differ: %dx%d and %dx%d" % (w1, h1, w2, h2))
        return 1
    diff = 0
    for y in range(h1):
        if r1[y] == r2[y]:
            continue
        for x in range(w1):
            if p1(r1[y], x) != p2(r2[y], x):
                diff += 1
    print("%d differing pixels of %d (%dx%d)" % (diff, w1 * h1, w1, h1))
    return 0 if diff == 0 else 1


def flatten(node, path="root"):
    """[(path, class, id, x, y, w, h)] in tree order."""
    out = [(path, node.get("class"), node.get("id"), node.get("x", 0), node.get("y", 0),
            node.get("width", 0), node.get("height", 0))]
    for i, c in enumerate(node.get("children", [])):
        out.extend(flatten(c, "%s/%d" % (path, i)))
    return out


def compare_json(name, a, b, tol):
    fails, warns = [], []
    fa, fb = flatten(a["root"]), flatten(b["root"])
    sa = [(p, c, i) for p, c, i, *_ in fa]
    sb = [(p, c, i) for p, c, i, *_ in fb]
    if sa != sb:
        first = next((k for k in range(min(len(sa), len(sb))) if sa[k] != sb[k]), min(len(sa), len(sb)))
        fails.append("view tree differs (%d vs %d views; first difference at %s: %s vs %s)"
                     % (len(sa), len(sb), (sa + sb)[first][0] if first < len(sa) else "end",
                        sa[first] if first < len(sa) else "-", sb[first] if first < len(sb) else "-"))
    else:
        worst = []
        for x, y in zip(fa, fb):
            d = max(abs(x[k] - y[k]) for k in range(3, 7))
            if d > tol:
                worst.append((d, x[0], x[1], x[2], x[3:], y[3:]))
        worst.sort(reverse=True)
        if worst:
            fails.append("%d frame(s) differ by more than %g px; largest: %s"
                         % (len(worst), tol, "; ".join("%s %s%s %g px (%s vs %s)" % (p, c, "#" + i if i else "", d, fx, fy)
                                                      for d, p, c, i, fx, fy in worst[:3])))
    if a.get("focusOrder") != b.get("focusOrder"):
        fails.append("Tab order differs: %s vs %s" % (a.get("focusOrder"), b.get("focusOrder")))
    la = {(f.get("rule"), f.get("id")) for f in a.get("lint", [])}
    lb = {(f.get("rule"), f.get("id")) for f in b.get("lint", [])}
    if la != lb:
        warns.append("lint differs: only first %s, only second %s" % (sorted(la - lb), sorted(lb - la)))
    for f in fails:
        print("FAIL %s: %s" % (name, f))
    for w in warns:
        print("WARN %s: %s" % (name, w))
    if not fails and not warns:
        print("ok   %s" % name)
    return len(fails)


def main(argv):
    if len(argv) == 4 and argv[1] == "--pixels":
        return pixels(argv[2], argv[3])
    args = [a for a in argv[1:]]
    tol = 24.0
    if "--tolerance" in args:
        i = args.index("--tolerance")
        tol = float(args[i + 1])
        del args[i:i + 2]
    if len(args) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    A, B = args
    fails = 0
    for d in (A, B):
        m = json.load(open(os.path.join(d, "manifest.json")))
        bad = [c["case"] for c in m["cases"] if c["status"] == "FAIL"]
        print("%s %s (%s at %s): %d case(s)%s" % ("FAIL" if bad else "ok  ", d, m["platform"], (m["commit"] or "?")[:12],
                                                len(m["cases"]), ", failed: " + ", ".join(bad) if bad else ""))
        fails += bool(bad)
    names = sorted(n for n in os.listdir(A) if n.endswith(".json") and n != "manifest.json"
                   and os.path.exists(os.path.join(B, n)))
    if not names:
        print("FAIL no frames JSON in common")
        return 1
    for n in names:
        fails += compare_json(n, json.load(open(os.path.join(A, n))), json.load(open(os.path.join(B, n))), tol)
    print("== %d file(s) compared, %s" % (len(names), "no failures" if not fails else "%d failure(s)" % fails))
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
