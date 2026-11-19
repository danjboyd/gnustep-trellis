#!/usr/bin/env python3
"""Regression checks for Tests/Parity/compare.py, on synthetic data only.

Builds pairs of run.sh-style output folders (a manifest and frames JSON)
in a temporary directory, runs compare.py on each pair and checks the exit
code and the verdict line it prints. Also checks --pixels on tiny PNGs.
Needs no GNUstep, so it runs in make check on every platform.
Prints PARITY-COMPARE OK, or the failing checks and exit 1.
"""
import copy
import json
import os
import struct
import subprocess
import sys
import tempfile
import zlib

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
COMPARE = os.path.join(HERE, "..", "Parity", "compare.py")


def frames():
    """A small frames JSON shaped like TrellisPreview --export-json."""
    def v(cls, id_, x, y, w, h, children=()):
        n = {"class": cls, "x": x, "y": y, "width": w, "height": h, "children": list(children)}
        if id_:
            n["id"] = id_
        return n
    root = v("TRBox", None, 0, 0, 900, 640, [
        v("NSTextField", "title", 0, 6, 131, 21),
        v("TRBox", "toolbar", 0, 40, 900, 32, [
            v("NSSearchField", "search", 0, 0, 300, 24),
            v("NSPopUpButton", "size", 308, 0, 120, 24),
            v("NSButton", None, 436, 0, 80, 24),
        ]),
        v("NSScrollView", "list", 0, 80, 900, 560),
    ])
    return {"root": root, "focusOrder": ["search", "size", "NSButton"],
            "lint": [{"rule": "text-clipped", "id": "title"}], "theme": "Adwaita"}


def manifest(platform, failed=()):
    names = ["open Adwaita-light", "resize Adwaita-light", "render Adwaita-light"]
    return {"platform": platform, "commit": "0123456789abcdef0123", "themes": ["Adwaita"],
            "cases": [{"case": n, "status": "FAIL" if n in failed else "PASS", "detail": ""} for n in names]}


def write_out(base, name, platform, data, failed=(), files=("open-Adwaita-light.json",)):
    d = os.path.join(base, name)
    os.makedirs(d)
    json.dump(manifest(platform, failed), open(os.path.join(d, "manifest.json"), "w"))
    for f in files:
        json.dump(data, open(os.path.join(d, f), "w"))
    return d


def png(path, w, h, colour_at):
    raw = b"".join(b"\0" + b"".join(bytes(colour_at(x, y)) for x in range(w)) for y in range(h))
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def run(*args):
    p = subprocess.run([sys.executable, "-I", COMPARE] + list(args), capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def main():
    bad, done = [], []

    def check(label, args, code, needle):
        done.append(label)
        rc, out = run(*args)
        if rc != code or needle not in out:
            bad.append("%s: exit %d (wanted %d), %r %s in:\n%s"
                       % (label, rc, code, needle, "missing" if needle not in out else "present", out))

    with tempfile.TemporaryDirectory(prefix="parity-cmp-") as t:
        base = frames()
        lin = write_out(t, "linux", "linux", base)

        def win(name, mutate=None, **kw):
            d = copy.deepcopy(base)
            if mutate:
                mutate(d)
            return write_out(t, name, "windows", d, **kw)

        check("identical", [lin, win("same")], 0, "ok   open-Adwaita-light.json")

        def nudge(px):
            def m(d):
                d["root"]["children"][1]["children"][1]["width"] += px
            return m
        check("within tolerance", [lin, win("near", nudge(10))], 0, "no failures")
        far = win("far", nudge(30))
        check("beyond tolerance", [lin, far], 1, "frame(s) differ by more than 24 px")
        check("largest frame named", [lin, far], 1, "NSPopUpButton#size 30 px")
        check("--tolerance widens", [lin, far, "--tolerance", "40"], 0, "no failures")
        check("--tolerance first", ["--tolerance", "40", lin, far], 0, "no failures")

        check("extra view", [lin, win("extra", lambda d: d["root"]["children"].append(
            {"class": "NSButton", "x": 0, "y": 0, "width": 1, "height": 1}))], 1, "view tree differs (7 vs 8 views; first difference at root/3: - vs")
        check("renamed id", [lin, win("renamed", lambda d: d["root"]["children"][0].update(id="heading"))],
              1, "view tree differs")
        check("reordered children", [lin, win("swapped", lambda d: d["root"]["children"][1]["children"].reverse())],
              1, "first difference at root/1/0")
        check("Tab order", [lin, win("tab", lambda d: d["focusOrder"].reverse())], 1, "Tab order differs")
        check("lint is a warning", [lin, win("lint", lambda d: d.update(lint=[]))], 0,
              "WARN open-Adwaita-light.json: lint differs: only first [('text-clipped', 'title')]")
        check("failed manifest case", [lin, win("failedcase", failed=("render Adwaita-light",))], 1,
              "failed: render Adwaita-light")
        check("no common files", [lin, win("other", files=("render-Adwaita-light.json",))], 1,
              "FAIL no frames JSON in common")
        both = ("open-Adwaita-light.json", "open-Adwaita-light-340x640.json")
        lin2 = write_out(t, "linux2", "linux", base, files=both)
        check("every common file", [lin2, win("two", files=both)], 0, "== 2 file(s) compared, no failures")
        check("only common files", [lin2, win("one")], 0, "== 1 file(s) compared")
        check("usage", [lin], 2, "compare.py LINUX_OUT WINDOWS_OUT")
        winui = win("winui", files=("open-WinUITheme-light.json",))
        check("theme-map pairs", [lin, winui, "--theme-map", "Adwaita=WinUITheme"], 0,
              "ok   open-Adwaita-light.json ~ open-WinUITheme-light.json")
        check("theme-map needed", [lin, winui], 1, "FAIL no frames JSON in common")
        check("theme-map compares", [lin, win("winuifar", nudge(30), files=("open-WinUITheme-light.json",)),
                                     "--theme-map", "Adwaita=WinUITheme"], 1, "frame(s) differ by more than 24 px")
        check("theme-map usage", [lin, winui, "--theme-map", "Adwaita"], 2, "--theme-map A=B")

        a, b, c, s = (os.path.join(t, n) for n in ("a.png", "b.png", "c.png", "s.png"))
        png(a, 8, 6, lambda x, y: (x * 30, y * 40, 200))
        png(b, 8, 6, lambda x, y: (x * 30, y * 40, 200))
        png(c, 8, 6, lambda x, y: (x * 30, y * 40, 201 if (x, y) in ((1, 1), (7, 5)) else 200))
        png(s, 6, 8, lambda x, y: (0, 0, 0))
        check("pixels equal", ["--pixels", a, b], 0, "0 differing pixels of 48 (8x6)")
        check("pixels differ", ["--pixels", a, c], 1, "2 differing pixels of 48")
        check("pixel sizes", ["--pixels", a, s], 1, "FAIL sizes differ: 8x6 and 6x8")

    if bad:
        print("PARITY-COMPARE FAIL (%d)" % len(bad))
        for b in bad:
            print("- " + b)
        return 1
    print("PARITY-COMPARE OK (%d checks)" % len(done))
    return 0


if __name__ == "__main__":
    sys.exit(main())
