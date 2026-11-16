#!/usr/bin/env python3
"""Import Yoga's generated gtest cases into Trellis conformance JSON.

Yoga (https://github.com/facebook/yoga, MIT licence) generates its C++
tests from HTML fixtures rendered in Chrome (gentest/fixtures/*.html).
The generated tests/generated/*.cpp files hold both the input tree and the
browser-measured frames, so we parse those rather than re-running Chrome.

Usage: import_yoga.py <yoga-checkout> <out-dir>

Each Yoga TEST becomes one case per layout direction (Yoga checks both LTR
and RTL), written to <out-dir>/<Category>/<test>.<dir>.json.

Notes on fidelity:
  * Gentest's page applies Yoga-flavoured defaults to every div (column
    direction, flex-shrink 0, align-content flex-start, border-box,
    position relative).  Trellis uses CSS defaults, so those base values are
    written explicitly into every node's style.
  * Yoga resolves edges by precedence (logical start/end, then the physical
    edge, then horizontal/vertical, then all), not by declaration order.  As
    each case has a fixed direction, we resolve to physical edges here so the
    case means the same thing to any CSS engine.
  * Yoga rounds layout to whole pixels, hence the 1px tolerance.
"""
import json
import os
import re
import subprocess
import sys

BASE_STYLE = {
    "display": "flex",
    "flexDirection": "column",
    "alignContent": "flex-start",
    "flexShrink": 0,
    "position": "relative",
}

ENUMS = {
    "YGFlexDirectionColumn": "column",
    "YGFlexDirectionColumnReverse": "column-reverse",
    "YGFlexDirectionRow": "row",
    "YGFlexDirectionRowReverse": "row-reverse",
    "YGJustifyFlexStart": "flex-start",
    "YGJustifyCenter": "center",
    "YGJustifyFlexEnd": "flex-end",
    "YGJustifySpaceBetween": "space-between",
    "YGJustifySpaceAround": "space-around",
    "YGJustifySpaceEvenly": "space-evenly",
    "YGAlignAuto": "auto",
    "YGAlignFlexStart": "flex-start",
    "YGAlignCenter": "center",
    "YGAlignFlexEnd": "flex-end",
    "YGAlignStretch": "stretch",
    "YGAlignBaseline": "baseline",
    "YGAlignSpaceBetween": "space-between",
    "YGAlignSpaceAround": "space-around",
    "YGAlignSpaceEvenly": "space-evenly",
    "YGPositionTypeStatic": "static",
    "YGPositionTypeRelative": "relative",
    "YGPositionTypeAbsolute": "absolute",
    "YGWrapNoWrap": "nowrap",
    "YGWrapWrap": "wrap",
    "YGWrapWrapReverse": "wrap-reverse",
    "YGOverflowVisible": "visible",
    "YGOverflowHidden": "hidden",
    "YGOverflowScroll": "scroll",
    "YGDisplayFlex": "flex",
    "YGDisplayNone": "none",
    "YGDisplayContents": "contents",
    "YGBoxSizingBorderBox": "border-box",
    "YGBoxSizingContentBox": "content-box",
}

SIMPLE = {  # Yoga setter stem -> CSS property
    "Width": "width", "Height": "height",
    "MinWidth": "minWidth", "MinHeight": "minHeight",
    "MaxWidth": "maxWidth", "MaxHeight": "maxHeight",
    "FlexBasis": "flexBasis", "FlexGrow": "flexGrow", "FlexShrink": "flexShrink",
    "FlexDirection": "flexDirection", "JustifyContent": "justifyContent",
    "AlignItems": "alignItems", "AlignSelf": "alignSelf",
    "AlignContent": "alignContent", "PositionType": "position",
    "FlexWrap": "flexWrap", "Overflow": "overflow", "Display": "display",
    "BoxSizing": "boxSizing", "AspectRatio": "aspectRatio",
}
EDGED = {"Margin": "margin", "Padding": "padding", "Border": "border",
         "Position": "inset"}
SUFFIX_KEYWORD = {"Auto": "auto", "MaxContent": "max-content",
                  "FitContent": "fit-content", "Stretch": "stretch"}

REQUIRES_BY_VALUE = {
    ("display", "contents"): "display-contents",
    ("position", "static"): "position-static",
    ("alignItems", "baseline"): "align-baseline",
    ("alignSelf", "baseline"): "align-baseline",
}
REQUIRES_BY_KEY = {"aspectRatio": "aspect-ratio", "overflow": "overflow",
                   "rowGap": "gap", "columnGap": "gap"}

TEST_RE = re.compile(r"^TEST\(YogaTest, (\w+)\) \{$")
CALL_RE = re.compile(r"^\s*(?:YGNodeRef (\w+) = )?(\w+)\((.*)\);\s*$")
ASSERT_RE = re.compile(
    r"^\s*ASSERT_FLOAT_EQ\((-?[\d.]+)f?, YGNodeLayoutGet(Left|Top|Width|Height)\((\w+)\)\);")


def num(tok):
    tok = tok.strip()
    if tok == "YGUndefined":
        return None
    tok = tok.rstrip("f")
    v = float(tok)
    return int(v) if v == int(v) else v


def split_args(s):
    # Arguments never contain commas except inside the string literal of
    # YGNodeSetContext, which is handled separately.
    return [a.strip() for a in s.split(",")]


class Node:
    def __init__(self, name):
        self.name = name
        self.calls = []          # (stem, edge/gutter or None, value)
        self.children = []
        self.text = None
        self.measured = False


def physical_edges(edges, direction):
    """edges: dict edge-name -> value. Return dict left/top/right/bottom."""
    start, end = ("Left", "Right") if direction == "ltr" else ("Right", "Left")
    out = {}
    for side in ("Left", "Top", "Right", "Bottom"):
        order = []
        if side == start:
            order.append("Start")
        if side == end:
            order.append("End")
        order.append(side)
        order.append("Horizontal" if side in ("Left", "Right") else "Vertical")
        order.append("All")
        for e in order:
            if e in edges:
                out[side.lower()] = edges[e]
                break
    return out


def node_style(node, direction, requires):
    style = dict(BASE_STYLE)
    edged = {}   # prop -> {edge: value}
    gaps = {}
    for stem, edge, value in node.calls:
        if stem in EDGED:
            edged.setdefault(stem, {})[edge] = value
        elif stem == "Gap":
            gaps[edge] = value
        else:
            prop = SIMPLE[stem]
            style[prop] = value
    for stem, edges in edged.items():
        for side, v in physical_edges(edges, direction).items():
            if stem == "Position":
                style[side] = v
            elif stem == "Border":
                style["border%sWidth" % side.capitalize()] = v
            else:
                style[EDGED[stem] + side.capitalize()] = v
    if gaps:
        row = gaps.get("Row", gaps.get("All"))
        col = gaps.get("Column", gaps.get("All"))
        if row is not None:
            style["rowGap"] = row
        if col is not None:
            style["columnGap"] = col
    for k, v in style.items():
        tag = REQUIRES_BY_VALUE.get((k, v)) or REQUIRES_BY_KEY.get(k)
        if tag:
            requires.add(tag)
        if isinstance(v, str) and v in ("max-content", "fit-content", "stretch") \
                and k not in ("alignItems", "alignSelf", "alignContent"):
            requires.add("intrinsic-size-keyword")
    return style


def build_tree(node, direction, requires, expected):
    out = {"style": node_style(node, direction, requires)}
    if node.text is not None:
        out["measure"] = {"text": node.text, "charWidth": 10, "lineHeight": 10}
        requires.add("measure")
    exp = {k: expected[node.name][k] for k in ("x", "y", "width", "height")}
    if node.children:
        kids = [build_tree(c, direction, requires, expected) for c in node.children]
        out["children"] = [k[0] for k in kids]
        exp["children"] = [k[1] for k in kids]
    return out, exp


def parse_call(nodes, fn, args_s):
    m = re.match(r"YGNodeStyleSet(\w+)", fn)
    if not m:
        return False
    rest = m.group(1)
    args = split_args(args_s)
    node = nodes[args[0]]
    # Edged / gutter properties
    for stem in list(EDGED) + ["Gap"]:
        if rest.startswith(stem) and (rest == stem or rest[len(stem):] in ("Percent", "Auto")):
            kind = rest[len(stem):]
            edge = re.sub(r"^YG(Edge|Gutter)", "", args[1])
            if kind == "Auto":
                value = "auto"
            else:
                value = num(args[2])
                if kind == "Percent":
                    value = "%s%%" % value
            node.calls.append((stem, edge, value))
            return True
    for suffix, kw in SUFFIX_KEYWORD.items():
        if rest.endswith(suffix) and rest[: -len(suffix)] in SIMPLE:
            node.calls.append((rest[: -len(suffix)], None, kw))
            return True
    if rest.endswith("Percent") and rest[:-7] in SIMPLE:
        node.calls.append((rest[:-7], None, "%s%%" % num(args[1])))
        return True
    if rest in SIMPLE:
        a = args[1]
        value = ENUMS[a] if a in ENUMS else num(a)
        node.calls.append((rest, None, value))
        return True
    raise ValueError("unhandled setter %s(%s)" % (fn, args_s))


def parse_file(path):
    tests = []
    cur = None
    with open(path) as f:
        lines = f.readlines()
    for line in lines:
        mt = TEST_RE.match(line)
        if mt:
            cur = {"name": mt.group(1), "nodes": {}, "root": None, "layouts": []}
            tests.append(cur)
            continue
        if cur is None:
            continue
        if line.startswith("}"):
            cur = None
            continue
        ma = ASSERT_RE.match(line)
        if ma:
            v, what, name = ma.groups()
            key = {"Left": "x", "Top": "y", "Width": "width", "Height": "height"}[what]
            cur["layouts"][-1]["expected"].setdefault(name, {})[key] = num(v)
            continue
        if "YGNodeSetContext" in line:
            ms = re.match(r'\s*YGNodeSetContext\((\w+), \(void\*\)"(.*)"\);', line)
            cur["nodes"][ms.group(1)].text = ms.group(2).encode().decode("unicode_escape")
            continue
        mc = CALL_RE.match(line)
        if not mc:
            continue
        var, fn, args_s = mc.groups()
        if fn == "YGNodeNewWithConfig":
            cur["nodes"][var] = Node(var)
            if cur["root"] is None:
                cur["root"] = var
        elif fn == "YGNodeInsertChild":
            p, c, i = split_args(args_s)
            cur["nodes"][p].children.insert(int(i), cur["nodes"][c])
        elif fn == "YGNodeSetMeasureFunc":
            a = split_args(args_s)
            if not a[1].endswith("IntrinsicSizeMeasure"):
                raise ValueError("unknown measure func %s in %s" % (a[1], cur["name"]))
            cur["nodes"][a[0]].measured = True
        elif fn == "YGNodeCalculateLayout":
            _, w, h, d = split_args(args_s)
            cur["layouts"].append({
                "available": {"width": num(w), "height": num(h)},
                "direction": "rtl" if d == "YGDirectionRTL" else "ltr",
                "expected": {},
            })
        elif fn in ("YGConfigNew", "YGConfigFree", "YGNodeFreeRecursive"):
            pass
        elif fn.startswith("YGConfig"):
            raise ValueError("unhandled config call %s in %s" % (fn, cur["name"]))
        else:
            parse_call(cur["nodes"], fn, args_s)
    return tests


def main():
    yoga, out_dir = sys.argv[1], sys.argv[2]
    commit = subprocess.run(["git", "-C", yoga, "rev-parse", "HEAD"],
                            capture_output=True, text=True, check=True).stdout.strip()
    gen = os.path.join(yoga, "tests", "generated")
    total = 0
    for fn in sorted(os.listdir(gen)):
        if not fn.endswith(".cpp"):
            continue
        stem = fn[:-4]
        category = re.sub(r"^YG|Test$", "", stem)
        for t in parse_file(os.path.join(gen, fn)):
            root = t["nodes"][t["root"]]
            for lay in t["layouts"]:
                requires = set()
                tree, exp = build_tree(root, lay["direction"], requires, lay["expected"])
                case = {
                    "id": "yoga/%s/%s/%s" % (category, t["name"], lay["direction"]),
                    "source": {
                        "suite": "yoga",
                        "file": "gentest/fixtures/%s.html" % stem,
                        "generated": "tests/generated/%s" % fn,
                        "test": t["name"],
                        "commit": commit,
                        "license": "MIT",
                        "copyright": "Meta Platforms, Inc. and affiliates",
                    },
                    "direction": lay["direction"],
                    "tolerance": 1.0,
                    "root": tree,
                    "expected": exp,
                }
                if lay["available"]["width"] is not None or lay["available"]["height"] is not None:
                    case["available"] = lay["available"]
                if t["name"].startswith("contains_inner_text"):
                    # Yoga's test measure function (tests/util/TestUtil.cpp)
                    # breaks over-long words differently from the Ahem-style
                    # stand-in; tag rather than mis-measure.
                    case["skip"] = ("Yoga's test measure function (tests/util/TestUtil.cpp) "
                                    "wraps over-long words differently from the Ahem stand-in")
                if requires:
                    case["requires"] = sorted(requires)
                d = os.path.join(out_dir, category)
                os.makedirs(d, exist_ok=True)
                with open(os.path.join(d, "%s.%s.json" % (t["name"], lay["direction"])), "w") as f:
                    json.dump(case, f, indent=1, sort_keys=False)
                    f.write("\n")
                total += 1
    print("yoga: wrote %d cases from %s" % (total, commit[:12]))


if __name__ == "__main__":
    main()
