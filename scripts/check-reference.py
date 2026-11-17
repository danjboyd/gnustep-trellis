#!/usr/bin/env python3
"""Compare Trellis frame dumps across platforms (Linux/GNUstep and macOS/Cocoa).

A frame dump is the JSON that `trellis-render --json` and TrellisPreview's
--export-json write. Fonts and control metrics differ between platforms, so
two renders of one spec never match pixel for pixel. This script separates
the layout engine from those metrics.

  replay DUMP...
      Rebuild each dump as engine cases and run them through this platform's
      trellis-case. Every node keeps its layout style. Every measured leaf
      (control, text) measures as the dump recorded it ("intrinsic", or
      "needed" for text; the frame for one that wrapped or shrank) with its
      recorded "baseline". Boxes, scroll views and split views stay
      unmeasured, as in Trellis. A scroll box's document and each split
      pane are cases of their own, at the size the dump gives them. A
      difference over a pixel is the engine laying out the same tree
      differently, never a font. Dumps from either platform replay on
      either.

  structure DUMP...
      Render the dump's source spec here, at the dump's viewport and
      appearance (with Name.sample.json beside the spec, if any), and
      compare the trees: same classes, ids, child counts and display:none
      nodes. Geometry differences are listed but don't fail, since they
      follow from text and control sizes.

  render OUTDIR [SPEC...]
      Write dumps here for every spec (default: Examples/TrellisDemo,
      Tests/Reference and dogfood, *.trellis) at widths 340, 520 and 900, 680 tall, light and
      dark. The other platform replays them: replay is symmetric, so
      `replay OUTDIR/*.json` on Linux checks macOS dumps and vice versa.

  selftest [DUMP...]
      Change one geometry value per dump (a leaf moved 5px; 5px more
      padding on a box) and check that replay catches each change.

  all [DUMP...]
      replay, then structure. With no dumps, every dump under dogfood/frames
      and Tests/Reference/dumps (golden dumps of Tests/Reference/*.trellis,
      one directory per platform that recorded them).

Exit status is 1 if replay finds a difference or structure finds a
structural mismatch. Run with python3 -I from the repository root.
"""
import argparse
import glob
import json
import os
import subprocess
import sys
import tempfile

# Style properties that never change geometry.
PAINT_ONLY = {
    "color", "background-color", "border-color", "border-radius",
    "font-weight", "font-style", "opacity", "cursor", "box-shadow",
    "text-align", "container-type", "container-name",
}
# font-size changes text size, but the leaf's size is fixed from the dump.
PAINT_ONLY |= {"font-size", "font-family", "line-height"}


# Dump frames are whole pixels (the engine rounds edges to the pixel grid),
# so a container with a fractional size (a grid track of 282/7) replays up to
# a pixel off. Anything larger is a real difference.
TOLERANCE = 1.0

# Classes whose children are a scrolled document, laid out on its own.
SCROLL_CLASSES = {"TRScrollBox", "NSScrollView"}
# Views laid out as boxes sized by their style, with no measure block: Trellis
# boxes (even empty ones) and scroll views.
UNMEASURED_CLASSES = SCROLL_CLASSES | {"TRBoxView", "TRVirtualBox", "TRSplitView"}


def parse_style(s):
    out = {}
    for part in (s or "").split(";"):
        if ":" not in part:
            continue
        k, v = part.split(":", 1)
        k, v = k.strip(), v.strip()
        if k and k not in PAINT_ONLY:
            out[k] = v
    return out


def px(v):
    v = (v or "").strip()
    return float(v[:-2]) if v.endswith("px") else 0.0


def is_leaf(n):
    # A virtual box realizes only the items in view, so its children are not
    # a tree the engine can lay out; it is compared as a box sized by style.
    return (not n.get("children") or n.get("class") in SCROLL_CLASSES or "virtual" in n
            or "split" in n)


def frame(n):
    return {k: n.get(k, 0) for k in ("x", "y", "width", "height")}


def build(n, docs, path):
    """Engine node and expected frames for dump node n. Scroll documents are
    appended to docs as (path, node, width, height, "scroll" | "pane" | "item")."""
    style = parse_style(n.get("style"))
    node, exp = {"style": style}, frame(n)
    # A hidden view (hidden= or -setHidden:forSubview:) is laid out as if
    # display: none, whatever its style says.
    if style.get("display") == "none" or n.get("hidden"):
        node["style"] = {"display": "none"}
        return node, None
    if is_leaf(n):
        # A scroll view has no measure in Trellis (TRBoxView
        # -attachSubview:declarations:): it is an empty box sized by its
        # style. Every other leaf measures at the size the dump recorded.
        # The leaf's measure: what Trellis's measure block returned, as the
        # dump records it ("needed" for text at its width, "intrinsic" for
        # a control). Otherwise (separators, image views) the frame's content
        # box, since the engine adds padding and border around a measure.
        # A leaf that ended up narrower than its intrinsic width (text that
        # wrapped, a label that shrank) measured at the width it was given,
        # which a fixed measure can only stand in for with the frame's.
        if n.get("class") not in UNMEASURED_CLASSES and "virtual" not in n:
            dx = sum(px(style.get(f"{k}-{e}")) for k in ("padding", "border") for e in ("left", "right"))
            dy = sum(px(style.get(f"{k}-{e}")) for k in ("padding", "border") for e in ("top", "bottom"))
            cw = max(0, n.get("width", 0) - dx)
            ch = max(0, n.get("height", 0) - dy)
            # "measured" (since 0.6.x) is the engine's own max-content measure;
            # older dumps only have the cell's "intrinsic" size.
            meas = n.get("measured")
            # A text view measures nothing without a width (GNUstep's
            # NSTextView gives 0x0 at max-content); an empty measure of a
            # non-empty frame says nothing, so fall back to the frame.
            if meas and (meas["width"] <= 0 or meas["height"] <= 0) and cw > 0 and ch > 0:
                meas = {"width": cw, "height": ch}
            m = n.get("needed") or meas or n.get("intrinsic")
            intr = meas or n.get("intrinsic") or m
            if m is None:
                node["measure"] = {"width": cw, "height": ch}
            elif cw < intr["width"] - 0.5:
                node["measure"] = {"width": cw, "height": m["height"]}
            elif "text" in n and ch > m["height"] + 0.5:
                # Text that wrapped at its frame's width although the dump's
                # single-line sizes say it fits (on GNUstep a wrapping
                # cell's cellSize follows its frame): the frame is the
                # measure the engine got.
                node["measure"] = {"width": cw, "height": ch}
            else:
                node["measure"] = {"width": m["width"], "height": m["height"]}
            if "baseline" in n:
                node["measure"]["baseline"] = n["baseline"]
        if n.get("class") in SCROLL_CLASSES:
            for i, d in enumerate(n.get("children") or []):
                # The document is as wide as the clip view: the scroll view
                # less a legacy scroller (GNUstep's is 19pt; macOS overlay
                # scrollers take none). Its own frame records that width.
                docs.append((f"{path}/scroll[{i}]", d, d.get("width", n.get("width", 0)),
                             n.get("height", 0), "scroll"))
        elif "split" in n:
            # NSSplitView places the panes; each pane lays out at its size.
            for i, d in enumerate(n.get("children") or []):
                if not d.get("hidden"):
                    docs.append((f"{path}/pane[{i}]", d, d.get("width", 0), d.get("height", 0), "pane"))
        elif "virtual" in n:
            # TRVirtualLayout places the realized items; each one lays out
            # its own content at the size it was given: natural height in a
            # single column, the row's height in a grid (its items stretch).
            mode = "item" if n["virtual"].get("columns", 1) <= 1 else "pane"
            for i, d in enumerate(n.get("children") or []):
                docs.append((f"{path}/item[{d.get('item', i)}]", d, d.get("width", 0),
                             d.get("height", 0), mode))
        return node, exp
    kids, kexp = [], []
    for i, c in enumerate(n.get("children") or []):
        cn, ce = build(c, docs, f"{path}/{c.get('id') or c.get('class')}[{i}]")
        kids.append(cn)
        kexp.append(ce)
    node["children"] = kids
    # trellis-case compares children by index; a display:none child has no
    # frame to compare, so give it the engine's (zero) frame.
    exp["children"] = [ce if ce is not None else {"x": 0, "y": 0, "width": 0, "height": 0}
                       for ce in kexp]
    return node, exp


def cases_for_dump(path):
    d = json.load(open(path))
    vp = d.get("viewport", {})
    root = d["root"]
    docs = []
    node, exp = build(root, docs, root.get("id") or "root")
    node["style"] = dict(node["style"], width=f"{vp.get('width', root['width'])}px",
                         height=f"{vp.get('height', root['height'])}px")
    exp["x"] = exp["y"] = 0
    name = os.path.basename(path)
    cases = [{"id": f"reference/{name}", "root": node, "expected": exp, "tolerance": TOLERANCE}]
    while docs:
        dpath, dn, w, h, mode = docs.pop(0)
        sub = []
        node, exp = build(dn, sub, dpath)
        if exp is None:
            continue
        node["style"].pop("height", None)
        if mode == "pane":
            node["style"] = dict(node["style"], width=f"{w}px", height=f"{h}px")
        elif mode == "item":
            node["style"] = dict(node["style"], width=f"{w}px")
        else:
            # A scroll document is laid out at the scroll box's width and its
            # natural height, but never shorter than the scroll box.
            node["style"] = dict(node["style"], width=f"{w}px", **{"min-height": f"{h}px"})
        exp["x"] = exp["y"] = 0
        cases.append({"id": f"reference/{name}:{dpath}", "root": node, "expected": exp,
                      "tolerance": TOLERANCE})
        docs.extend(sub)
    return cases


def replay(dumps, runner, quiet=False):
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        for p in dumps:
            cases = cases_for_dump(p)
            f = os.path.join(tmp, os.path.basename(p))
            json.dump(cases, open(f, "w"))
            r = subprocess.run([runner, "--all", "-v", f], capture_output=True, text=True)
            lines = (r.stdout + r.stderr).splitlines()
            summary = next((l for l in reversed(lines) if l.startswith("PASS")), "?")
            ok = r.returncode == 0 and " fail 0 " in summary + " "
            if not quiet:
                print(f"{'ok  ' if ok else 'FAIL'} replay {p}: {len(cases)} case(s); {summary}")
            if not ok and quiet:
                bad += 1
            elif not ok:
                bad += 1
                case = None
                for l in lines:
                    if l.startswith("FAIL "):
                        case = l.split(" ")[1]
                    elif case and "expected" in l:
                        print(f"     {case}: {l.strip()}")
                        case = None  # first difference per case
    return bad


def shape(n, path="root"):
    """Flattened structure: (path, class, id, display:none) per node."""
    style = parse_style(n.get("style"))
    out = [(path, n.get("class"), n.get("id"), style.get("display") == "none" or bool(n.get("hidden")))]
    for i, c in enumerate(n.get("children") or []):
        out += shape(c, f"{path}/{c.get('id') or c.get('class')}[{i}]")
    return out


def frames(n, path="root", out=None):
    out = {} if out is None else out
    out[path] = (n.get("class"), frame(n), "intrinsic" in n)
    for i, c in enumerate(n.get("children") or []):
        frames(c, f"{path}/{c.get('id') or c.get('class')}[{i}]", out)
    return out


def structure(dumps, render, appearance, geometry_limit):
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        for p in dumps:
            ref = json.load(open(p))
            src = ref.get("source")
            vp = ref.get("viewport", {})
            if not src or not os.path.exists(src):
                print(f"skip structure {p}: source {src!r} not found")
                continue
            out = os.path.join(tmp, "here.json")
            cmd = [render, src, "--width", str(vp.get("width")), "--height", str(vp.get("height")),
                   "--json", out]
            sample = os.path.splitext(src)[0] + ".sample.json"
            if os.path.exists(sample):
                cmd += ["--sample", sample]
            ap = ref.get("appearance") or appearance
            if ap:
                cmd += ["--appearance", ap]
            if os.path.exists(out):
                os.remove(out)
            r = subprocess.run(cmd, capture_output=True, text=True)
            # Non-zero on lint findings (the before-* specs); the dump is
            # still written, as in render mode.
            if not os.path.exists(out):
                print(f"FAIL structure {p}: render failed: {(r.stderr or r.stdout).strip()[-200:]}")
                bad += 1
                continue
            here = json.load(open(out))
            a, b = shape(ref["root"]), shape(here["root"])
            diffs = []
            for i in range(max(len(a), len(b))):
                x = a[i] if i < len(a) else None
                y = b[i] if i < len(b) else None
                if x != y:
                    diffs.append(f"reference {x} / here {y}")
                    if len(diffs) >= 5:
                        break
            fa, fb = frames(ref["root"]), frames(here["root"])
            moved = []
            for k, (cls, f1, intr) in fa.items():
                if k not in fb:
                    continue
                f2 = fb[k][1]
                dmax = max(abs(f1[q] - f2[q]) for q in f1)
                if dmax > 0.5:
                    moved.append((dmax, k, cls, intr, f1, f2))
            moved.sort(key=lambda m: -m[0])
            boxes = [m for m in moved if not m[3]]
            print(f"{'FAIL' if diffs else 'ok  '} structure {p}: {len(a)} nodes reference, "
                  f"{len(b)} here; {len(moved)} frame(s) differ "
                  f"({len(moved) - len(boxes)} intrinsic leaves, {len(boxes)} boxes)")
            for d in diffs:
                print("     " + d)
            for dmax, k, cls, intr, f1, f2 in moved[:geometry_limit]:
                fmt = lambda f: f"{f['x']:g},{f['y']:g} {f['width']:g}x{f['height']:g}"
                print(f"     {'leaf' if intr else 'box '} {k} ({cls}): {fmt(f1)} -> {fmt(f2)}")
            bad += bool(diffs)
    return bad


def _checked_nodes(n, out, top=True):
    """(node, is_leaf) for the main-tree nodes replay compares, root excluded."""
    style = parse_style(n.get("style"))
    if style.get("display") == "none" or n.get("hidden"):
        return out
    if not top:
        out.append((n, is_leaf(n)))
    if not is_leaf(n):
        for c in n.get("children") or []:
            _checked_nodes(c, out, False)
    return out


def selftest(dumps, runner):
    """Check that replay catches a changed geometry value: for each dump,
    move one leaf 5px (an expected frame changes) and add 5px of
    padding-left to one box with children (a layout input changes). Both
    must make the replay fail; a dump that still passes means the checker
    is blind there."""
    caught = total = 0
    with tempfile.TemporaryDirectory() as tmp:
        for p in dumps:
            base = json.load(open(p))
            for kind in ("leaf-x", "box-padding"):
                d = json.loads(json.dumps(base))
                nodes = _checked_nodes(d["root"], [])
                if kind == "leaf-x":
                    pick = [n for n, leaf in nodes if leaf and n.get("width", 0) > 0]
                    if not pick:
                        continue
                    target = pick[len(pick) // 2]
                    target["x"] = target.get("x", 0) + 5
                else:
                    pick = [n for n, leaf in nodes if not leaf and n.get("children")]
                    if not pick:
                        continue
                    target = pick[len(pick) // 2]
                    st = parse_style(target.get("style"))
                    pad = px(st.get("padding-left")) + 5
                    target["style"] = (target.get("style") or "") + f"; padding-left: {pad:g}px"
                f = os.path.join(tmp, os.path.basename(p))
                json.dump(d, open(f, "w"))
                hit = replay([f], runner, quiet=True) > 0
                total += 1
                caught += hit
                if not hit:
                    print(f"MISS selftest {p}: {kind} on {target.get('class')} {target.get('id', '')} not caught")
    print(f"{'ok  ' if caught == total else 'FAIL'} selftest: {caught}/{total} changed values caught")
    return 0 if caught == total else 1


def default_specs():
    return sorted(glob.glob("Examples/TrellisDemo/*.trellis") + glob.glob("Tests/Reference/*.trellis")
                  + glob.glob("dogfood/**/*.trellis", recursive=True))


def render_all(outdir, specs, render, widths, height, appearances):
    os.makedirs(outdir, exist_ok=True)
    bad = n = 0
    for spec in specs:
        sample = os.path.splitext(spec)[0] + ".sample.json"
        parts = [q for q in os.path.normpath(os.path.splitext(spec)[0]).split(os.sep)
                 if q not in ("", ".", "..")]
        stem = "_".join(parts)
        for ap in appearances:
            for w in widths:
                out = os.path.join(outdir, f"{stem}-{ap}-{w}.json")
                cmd = [render, spec, "--width", str(w), "--height", str(height),
                       "--appearance", ap, "--json", out]
                if os.path.exists(sample):
                    cmd += ["--sample", sample]
                if os.path.exists(out):
                    os.remove(out)
                r = subprocess.run(cmd, capture_output=True, text=True)
                # trellis-render exits non-zero on lint findings; the dump is
                # still written, and lint isn't this script's concern.
                if not os.path.exists(out):
                    print(f"FAIL render {spec} {ap} {w}: {(r.stderr or r.stdout).strip()[-200:]}")
                    bad += 1
                    continue
                d = json.load(open(out))
                d["appearance"] = d.get("appearance") or ap
                json.dump(d, open(out, "w"), indent=1, sort_keys=True)
                n += 1
    print(f"{'FAIL' if bad else 'ok  '} render: {n} dump(s) in {outdir}, {bad} failed")
    return bad


def default_dumps():
    return sorted(glob.glob("dogfood/frames/*.json")
                  + glob.glob("Tests/Reference/dumps/**/*.json", recursive=True))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["replay", "structure", "render", "selftest", "all"])
    ap.add_argument("dumps", nargs="*")
    # Makefile.macos builds into build/, GNUmakefile into obj/.
    built = lambda t: f"build/{t}" if os.path.exists(f"build/{t}") else f"obj/{t}"
    ap.add_argument("--runner", default=os.environ.get("CASE", built("trellis-case")))
    ap.add_argument("--render", default=os.environ.get("RENDER", built("trellis-render")))
    ap.add_argument("--appearance", default=None,
                    help="appearance for renders when the dump doesn't name one")
    ap.add_argument("--geometry", type=int, default=5,
                    help="frame differences to list per dump in structure mode")
    ap.add_argument("--widths", default="340,520,900")
    ap.add_argument("--height", type=int, default=680)
    ap.add_argument("--appearances", default="light,dark")
    a = ap.parse_intermixed_args()
    if a.mode == "render":
        if not a.dumps:
            ap.error("render needs OUTDIR")
        bad = render_all(a.dumps[0], a.dumps[1:] or default_specs(), a.render,
                         [int(w) for w in a.widths.split(",")], a.height, a.appearances.split(","))
        print("CHECKREFERENCE " + ("FAIL" if bad else "OK"))
        return 1 if bad else 0
    dumps = a.dumps or default_dumps()
    if not dumps:
        print("no dumps")
        return 2
    bad = 0
    if a.mode == "selftest":
        bad += selftest(dumps, a.runner)
    if a.mode in ("replay", "all"):
        bad += replay(dumps, a.runner)
    if a.mode in ("structure", "all"):
        bad += structure(dumps, a.render, a.appearance, a.geometry)
    print("CHECKREFERENCE " + ("FAIL" if bad else "OK"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
