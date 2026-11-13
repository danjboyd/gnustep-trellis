#!/usr/bin/env python3
"""Import WPT css-flexbox check-layout tests into Trellis conformance JSON.

Usage: import_wpt.py <wpt-checkout> <out-dir> [subdir=css/css-flexbox]

web-platform-tests (https://github.com/web-platform-tests/wpt, 3-Clause BSD)
has many layout tests that call checkLayout(selector) from
resources/check-layout-th.js. That helper compares each element's
data-expected-width/height (offsetWidth/Height) and data-offset-x/y
(offsetLeft/Top) attributes with the browser's layout. Those tests are
machine-translatable; reftests are not, and are ignored.

The importer resolves the page's <style> rules and inline styles with a small
cascade, so every case carries computed-ish declarations per node. It
translates a test only when it can do so faithfully, and records a reason for
every test it skips (see the summary it prints).

Mapping:
  * data-expected-width/height -> expected width/height (border box).
  * data-offset-x/y are relative to the offsetParent's padding edge. Trellis
    frames are relative to the parent's border-box origin, so the importer
    adds the offsetParent's border widths and, if the offsetParent is not the
    direct parent, sets "relativeTo": k (the ancestor k levels up). Offsets
    whose offsetParent is outside the checked subtree are dropped.
  * The root of each case is laid out in the WPT viewport's body content
    box: 800px wide minus body's default 8px margins = 784px.
  * Ahem text becomes a measure stand-in (charWidth = font size).
  * check-layout-th's tolerance is |actual - expected| < 1.
"""
import collections
import html.parser
import json
import os
import re
import subprocess
import sys

VIEWPORT_CONTENT_WIDTH = 784
DEFAULT_FONT_SIZE = 16

VISUAL_PROPS = re.compile(
    r"^(background.*|color|outline.*|box-shadow|cursor|opacity|z-index|"
    r"border(-(top|right|bottom|left))?-color|border.*radius|font-family|"
    r"font-weight|font-style|text-decoration.*|list-style.*|transition.*|"
    r"animation.*|content|visibility|-webkit-.*|will-change|caret-color|"
    r"text-shadow|filter|scrollbar.*|forced-color-adjust)$")
SKIP_PROPS = {
    "writing-mode": "writing-mode",
    "text-orientation": "writing-mode",
    "transform": "transform",
    "zoom": "zoom",
    "contain": "contain",
    "container-type": "container-queries",
    "columns": "multicol", "column-count": "multicol", "column-width": "multicol",
    "anchor-name": "anchor", "position-anchor": "anchor",
    "contain-intrinsic-size": "contain",
    "table-layout": "table",
}
REPLACED = {"img", "input", "canvas", "svg", "video", "iframe", "button",
            "select", "textarea", "object", "embed", "math", "table", "audio",
            "picture", "progress", "meter", "fieldset", "legend", "details",
            "summary", "marquee", "hr", "ul", "ol", "li", "dl", "dt", "dd"}
IGNORED_TAGS = {"script", "style", "link", "title", "meta", "head", "html",
                "br", "wbr", "template", "noscript"}
DEFAULT_DISPLAY = {"div": "block", "p": "block", "section": "block",
                   "article": "block", "main": "block", "header": "block",
                   "footer": "block", "nav": "block", "aside": "block",
                   "body": "block", "html": "block", "span": "inline", "b": "inline",
                   "i": "inline", "em": "inline", "strong": "inline",
                   "a": "inline", "code": "inline", "h1": "block",
                   "h2": "block", "h3": "block", "h4": "block"}
UA_MARGINS = {"p": "1em 0", "h1": "0.67em 0", "h2": "0.83em 0",
              "h3": "1em 0", "h4": "1.33em 0"}
SIDES = ("top", "right", "bottom", "left")


class Skip(Exception):
    pass


# ---------------------------------------------------------------- DOM -------

class El:
    def __init__(self, tag, attrs, parent):
        self.tag = tag
        self.attrs = dict(attrs)
        self.parent = parent
        self.children = []      # El or str
        self.classes = set((self.attrs.get("class") or "").split())
        self.id = self.attrs.get("id")

    def element_children(self):
        return [c for c in self.children if isinstance(c, El)]


class DomBuilder(html.parser.HTMLParser):
    VOID = {"img", "input", "br", "hr", "meta", "link", "wbr", "source",
            "col", "embed", "area", "base", "param", "track"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.doc = El("#document", {}, None)
        self.cur = self.doc
        self.styles = []
        self.scripts = []
        self.doctype = False
        self._in = None
        self.body = None

    def handle_decl(self, decl):
        if decl.lower().startswith("doctype"):
            self.doctype = True

    def handle_starttag(self, tag, attrs):
        if tag == "body":
            el = El(tag, attrs, self.cur)
            self.cur.children.append(el)
            self.cur = el
            self.body = el
            return
        if tag in ("style", "script"):
            self._in = (tag, dict(attrs))
            self._buf = []
            return
        el = El(tag, attrs, self.cur)
        self.cur.children.append(el)
        if tag not in self.VOID:
            self.cur = el

    def handle_startendtag(self, tag, attrs):
        if tag in ("style", "script"):
            self.handle_starttag(tag, attrs)
            self.handle_endtag(tag)
            return
        el = El(tag, attrs, self.cur)
        self.cur.children.append(el)

    def handle_endtag(self, tag):
        if self._in and tag == self._in[0]:
            text = "".join(self._buf)
            if tag == "style":
                self.styles.append(text)
            else:
                self.scripts.append((self._in[1], text))
            self._in = None
            return
        # Pop up to the matching element (tolerates omitted end tags).
        n = self.cur
        while n is not None and n.tag != tag:
            n = n.parent
        if n is not None and n.parent is not None:
            self.cur = n.parent

    def handle_data(self, data):
        if self._in:
            self._buf.append(data)
        else:
            self.cur.children.append(data)


# ------------------------------------------------------------ CSS ----------

def strip_comments(css):
    return re.sub(r"/\*.*?\*/", "", css, flags=re.S)


def parse_decls(text):
    out = []
    for part in text.split(";"):
        if ":" not in part:
            continue
        k, v = part.split(":", 1)
        k = k.strip().lower()
        v = v.strip()
        important = False
        if v.lower().endswith("!important"):
            important = True
            v = v[: -len("!important")].strip()
        if k and v:
            out.append((k, v, important))
    return out


def parse_stylesheet(css):
    css = strip_comments(css)
    rules = []
    pos = 0
    while True:
        i = css.find("{", pos)
        if i < 0:
            break
        sel = css[pos:i].strip()
        if sel.startswith("@"):
            if sel.startswith("@font-face"):
                j = css.find("}", i)
                pos = j + 1
                continue
            raise Skip("at-rule " + sel.split()[0])
        j = css.find("}", i)
        rules.append((sel, parse_decls(css[i + 1:j])))
        pos = j + 1
    return rules


COMPOUND_RE = re.compile(r"^(\*|[a-zA-Z][\w-]*)?((?:[.#][\w-]+)*)((?::[\w-]+(?:\([^)]*\))?)*)$")


def parse_selector(sel):
    """Return list of (combinator, compound) from left to right."""
    sel = re.sub(r"\s*>\s*", " > ", sel.strip())
    sel = re.sub(r"\s*\+\s*", " + ", sel)
    sel = re.sub(r"\s*~\s*", " ~ ", sel)
    toks = sel.split()
    parts = []
    comb = None
    for t in toks:
        if t in (">", "+", "~"):
            comb = t
            continue
        m = COMPOUND_RE.match(t)
        if not m:
            raise Skip("selector " + t)
        tag, rest, pseudos = m.groups()
        classes = set(re.findall(r"\.([\w-]+)", rest))
        ids = re.findall(r"#([\w-]+)", rest)
        pseudo = re.findall(r":([\w-]+(?:\([^)]*\))?)", pseudos)
        for p in pseudo:
            if not re.match(r"^(first-child|last-child|nth-child\(\d+\)|nth-child\((odd|even)\)|nth-of-type\(\d+\)|first-of-type|last-of-type|only-child|not\(\.[\w-]+\))$", p):
                raise Skip("pseudo :" + p)
        parts.append((comb or " ", {"tag": None if tag in (None, "*") else tag.lower(),
                                     "classes": classes, "ids": ids, "pseudo": pseudo}))
        comb = None
    return parts


def specificity(parts):
    a = b = c = 0
    for _, comp in parts:
        a += len(comp["ids"])
        b += len(comp["classes"]) + len(comp["pseudo"])
        c += 1 if comp["tag"] else 0
    return (a, b, c)


def siblings(el):
    return el.parent.element_children() if el.parent else [el]


def match_compound(el, comp):
    if not isinstance(el, El) or el.tag.startswith("#"):
        return False
    if comp["tag"] and el.tag != comp["tag"]:
        return False
    if not comp["classes"] <= el.classes:
        return False
    for i in comp["ids"]:
        if el.id != i:
            return False
    for p in comp["pseudo"]:
        sib = siblings(el)
        idx = sib.index(el) + 1
        typed = [s for s in sib if s.tag == el.tag]
        tidx = typed.index(el) + 1
        if p == "first-child" and idx != 1:
            return False
        if p == "last-child" and idx != len(sib):
            return False
        if p == "only-child" and len(sib) != 1:
            return False
        if p == "first-of-type" and tidx != 1:
            return False
        if p == "last-of-type" and tidx != len(typed):
            return False
        m = re.match(r"nth-child\((\d+|odd|even)\)", p)
        if m:
            n = m.group(1)
            if n == "odd" and idx % 2 != 1:
                return False
            if n == "even" and idx % 2 != 0:
                return False
            if n.isdigit() and idx != int(n):
                return False
        m = re.match(r"nth-of-type\((\d+)\)", p)
        if m and tidx != int(m.group(1)):
            return False
        m = re.match(r"not\(\.([\w-]+)\)", p)
        if m and m.group(1) in el.classes:
            return False
    return True


def match_selector(el, parts):
    def rec(el, i):
        comb, comp = parts[i]
        if not match_compound(el, comp):
            return False
        if i == 0:
            return True
        if comb == ">":
            return el.parent is not None and rec(el.parent, i - 1)
        if comb == " ":
            p = el.parent
            while p is not None:
                if rec(p, i - 1):
                    return True
                p = p.parent
            return False
        sib = siblings(el)
        k = sib.index(el)
        if comb == "+":
            return k > 0 and rec(sib[k - 1], i - 1)
        if comb == "~":
            return any(rec(s, i - 1) for s in sib[:k])
        return False
    return rec(el, len(parts) - 1)


# --------------------------------------------------------- values ----------

LEN_RE = re.compile(r"^(-?\d*\.?\d+)(px|em|%)?$")


def to_px(v, font_size):
    """Convert a single length token. Returns number (px), '<n>%' or None."""
    v = v.strip()
    if v == "0":
        return 0
    m = LEN_RE.match(v)
    if not m:
        return None
    n = float(m.group(1))
    unit = m.group(2)
    if unit == "em":
        n *= font_size
    elif unit == "%":
        return "%s%%" % fmt(n)
    elif unit is None and n != 0:
        return None
    return fmt(n)


def fmt(n):
    return int(n) if float(n) == int(n) else round(n, 4)


def norm_value(v, font_size, requires):
    """Turn a declared value into a number (px) or a cleaned CSS string."""
    v = re.sub(r"\s+", " ", v.strip())
    if "calc(" in v or "min(" in v or "max(" in v or "clamp(" in v:
        requires.add("calc")
    if re.search(r"\d(vw|vh|vmin|vmax|ch|ex|rem|lh|cqw|cqh|in|cm|mm|pt|pc|q)\b", v):
        raise Skip("unit in " + v)
    p = to_px(v, font_size)
    if isinstance(p, (int, float)):
        return p
    # Convert em lengths inside multi-token values.
    def repl(m):
        return "%spx" % fmt(float(m.group(1)) * font_size)
    return re.sub(r"(-?\d*\.?\d+)em\b", repl, v)


def box4(v):
    t = v.split()
    if len(t) == 1:
        t = t * 4
    elif len(t) == 2:
        t = [t[0], t[1], t[0], t[1]]
    elif len(t) == 3:
        t = [t[0], t[1], t[2], t[1]]
    return dict(zip(SIDES, t[:4]))


BORDER_STYLES = {"none", "hidden", "dotted", "dashed", "solid", "double",
                 "groove", "ridge", "inset", "outset"}
BORDER_WIDTH_KW = {"thin": "1px", "medium": "3px", "thick": "5px"}


def parse_border(v):
    width = style = None
    for t in v.split():
        tl = t.lower()
        if tl in BORDER_STYLES:
            style = tl
        elif tl in BORDER_WIDTH_KW:
            width = BORDER_WIDTH_KW[tl]
        elif LEN_RE.match(tl) or tl == "0":
            width = tl
    return width, style


def expand(decls):
    """Fold an ordered list of (prop, value) into a longhand dict."""
    out = collections.OrderedDict()
    bw = {s: "3px" for s in SIDES}       # initial border-width: medium
    bs = {s: "none" for s in SIDES}
    for k, v in decls:
        if k in ("margin", "padding", "inset"):
            pre = "" if k == "inset" else k + "-"
            for s, x in box4(v).items():
                out[pre + s] = x
        elif k in ("gap", "grid-gap"):
            t = v.split()
            out["row-gap"] = t[0]
            out["column-gap"] = t[1] if len(t) > 1 else t[0]
        elif k == "flex":
            out.update(expand_flex(v))
        elif k == "flex-flow":
            for t in v.split():
                if t in ("row", "row-reverse", "column", "column-reverse"):
                    out["flex-direction"] = t
                else:
                    out["flex-wrap"] = t
        elif k == "border":
            w, st = parse_border(v)
            for s in SIDES:
                bw[s] = w or "3px"
                bs[s] = st or "none"
        elif re.match(r"^border-(top|right|bottom|left)$", k):
            s = k.split("-")[1]
            w, st = parse_border(v)
            bw[s] = w or "3px"
            bs[s] = st or "none"
        elif k == "border-width":
            for s, x in box4(v).items():
                bw[s] = BORDER_WIDTH_KW.get(x, x)
        elif k == "border-style":
            for s, x in box4(v).items():
                bs[s] = x
        elif re.match(r"^border-(top|right|bottom|left)-width$", k):
            bw[k.split("-")[1]] = BORDER_WIDTH_KW.get(v, v)
        elif re.match(r"^border-(top|right|bottom|left)-style$", k):
            bs[k.split("-")[1]] = v
        elif k in ("margin-inline-start", "margin-inline-end", "padding-inline-start",
                   "padding-inline-end", "inset-inline-start", "inset-inline-end",
                   "margin-block-start", "margin-block-end", "padding-block-start",
                   "padding-block-end", "inset-block-start", "inset-block-end",
                   "margin-inline", "margin-block", "padding-inline", "padding-block",
                   "inline-size", "block-size", "min-inline-size", "min-block-size",
                   "max-inline-size", "max-block-size", "inset-inline", "inset-block"):
            out[k] = v   # logical: left to the engine, tagged later
        else:
            out[k] = v
    for s in SIDES:
        if bs[s] not in ("none", "hidden"):
            out["border-%s-width" % s] = bw[s]
    return out


def expand_flex(v):
    t = v.split()
    num = re.compile(r"^-?\d*\.?\d+$")
    if v == "none":
        return {"flex-grow": "0", "flex-shrink": "0", "flex-basis": "auto"}
    if v == "auto":
        return {"flex-grow": "1", "flex-shrink": "1", "flex-basis": "auto"}
    if v == "initial":
        return {"flex-grow": "0", "flex-shrink": "1", "flex-basis": "auto"}
    if len(t) == 1:
        if num.match(t[0]):
            return {"flex-grow": t[0], "flex-shrink": "1", "flex-basis": "0%"}
        return {"flex-grow": "1", "flex-shrink": "1", "flex-basis": t[0]}
    if len(t) == 2:
        if num.match(t[1]):
            return {"flex-grow": t[0], "flex-shrink": t[1], "flex-basis": "0%"}
        return {"flex-grow": t[0], "flex-shrink": "1", "flex-basis": t[1]}
    return {"flex-grow": t[0], "flex-shrink": t[1], "flex-basis": t[2]}


def camel(k):
    return re.sub(r"-([a-z])", lambda m: m.group(1).upper(), k)


# -------------------------------------------------------- importer ---------

class Page:
    def __init__(self, path):
        with open(path, encoding="utf-8", errors="replace") as f:
            self.src = f.read()
        b = DomBuilder()
        b.feed(self.src)
        self.dom = b
        if not b.doctype:
            raise Skip("quirks mode")
        self.rules = []
        order = 0
        for css in b.styles:
            for sel, decls in parse_stylesheet(css):
                for s in sel.split(","):
                    s = s.strip()
                    try:
                        parts = parse_selector(s)
                    except Skip:
                        # A rule we can't match only matters if it could hit
                        # the tested subtree; be conservative and skip.
                        raise
                    self.rules.append((parts, specificity(parts), order, decls))
                    order += 1
        self.cache = {}

    def declared(self, el):
        if id(el) in self.cache:
            return self.cache[id(el)]
        matched = []
        for parts, spec, order, decls in self.rules:
            if match_selector(el, parts):
                for k, v, imp in decls:
                    matched.append(((imp, spec, order), k, v))
        for k, v, imp in parse_decls(el.attrs.get("style", "")):
            matched.append(((imp, (1, 0, 0, 0), 1 << 30), k, v))
        matched.sort(key=lambda m: m[0])
        ua = []
        if el.tag in UA_MARGINS:
            ua.append(("margin", UA_MARGINS[el.tag]))
        res = expand(ua + [(k, v) for _, k, v in matched])
        self.cache[id(el)] = res
        return res

    def font(self, el):
        """Return (font_size_px, family, line_height) inherited."""
        chain = []
        n = el
        while isinstance(n, El) and not n.tag.startswith("#"):
            chain.append(n)
            n = n.parent
        size, fam, lh = DEFAULT_FONT_SIZE, None, "normal"
        for n in reversed(chain):
            d = self.declared(n)
            if "font" in d:
                m = re.match(r"^(?:.*?\s)?(\d*\.?\d+)px(?:/(\S+))?\s+(.+)$", d["font"])
                if m:
                    size = float(m.group(1))
                    lh = m.group(2) or "normal"
                    fam = m.group(3).strip().strip("'\"")
            if "font-size" in d:
                p = to_px(d["font-size"], size)
                if isinstance(p, (int, float)):
                    size = p
            if "font-family" in d:
                fam = d["font-family"].strip().strip("'\"")
            if "line-height" in d:
                lh = d["line-height"]
        return size, fam, lh


def find_check_calls(page):
    calls = []
    body = page.dom.body
    if body is not None and "onload" in body.attrs:
        calls.append(body.attrs["onload"])
    for attrs, text in page.dom.scripts:
        if attrs.get("src"):
            continue
        calls.append(text)
    code = "\n".join(calls)
    sels = re.findall(r"checkLayout\(\s*(['\"])(.*?)\1", code)
    if not sels:
        raise Skip("no static checkLayout call")
    # Anything beyond checkLayout(...) calls means the page mutates or
    # measures state first.
    residue = re.sub(r"checkLayout\([^)]*\)\s*;?", "", code)
    residue = re.sub(r"window\.onload\s*=\s*\(?\s*(function\s*\(\)|\(\)\s*=>)\s*\{?|[{}();\s]|"
                     r"document\.fonts\.ready\.then|done\(\)|setup\([^)]*\)|"
                     r"//[^\n]*|addEventListener\(['\"]load['\"],|explicit_done|true|false|:|,|"
                     r"=>|function", "", residue)
    if residue.strip():
        raise Skip("script mutates page")
    return [s for _, s in sels]


def select_all(page, selector):
    out = []
    groups = [parse_selector(s) for s in selector.split(",")]

    def walk(el):
        for c in el.element_children():
            if any(match_selector(c, g) for g in groups):
                out.append(c)
            walk(c)
    walk(page.dom.doc)
    return out


class Converter:
    def __init__(self, page):
        self.page = page
        self.requires = set()
        self.direction = "ltr"
        self.root_sizing = None
        self.checked = set()
        self.checks = 0
        self.dropped = 0

    def display(self, el):
        d = self.page.declared(el)
        return d.get("display", DEFAULT_DISPLAY.get(el.tag, "inline"))

    def position(self, el):
        return self.page.declared(el).get("position", "static")

    def style_for(self, el, parent_display, is_root=False):
        d = self.page.declared(el)
        fs = self.page.font(el)[0]
        style = collections.OrderedDict()
        disp = self.display(el)
        if parent_display in ("flex", "inline-flex") and disp in ("inline", "inline-block"):
            disp = "block"   # flex items are blockified
        if disp == "inline-flex":
            self.requires.add("display-inline-flex")
        elif disp not in ("flex", "none", "block"):
            self.requires.add("display-" + disp)
        style["display"] = disp
        for k, v in d.items():
            if k in ("display", "font", "font-size", "line-height"):
                continue
            if VISUAL_PROPS.match(k):
                continue
            if k in SKIP_PROPS:
                raise Skip(SKIP_PROPS[k])
            if k == "direction":
                if not is_root:
                    raise Skip("direction set below case root")
                self.direction = v.strip()
                continue
            if k == "float":
                if parent_display in ("flex", "inline-flex") and not is_root:
                    continue        # floats don't apply to flex items
                if is_root:
                    if v.strip() != "none":
                        self.root_sizing = "fit-content"
                    continue
                if v.strip() != "none":
                    raise Skip("float")
                continue
            if k.startswith("grid") or k == "order" and False:
                self.requires.add("grid")
            if re.search(r"(inline|block)", k) and k not in ("display",):
                self.requires.add("logical-properties")
            val = norm_value(v, fs, self.requires)
            if isinstance(val, str):
                if re.search(r"\b(min-content|max-content|fit-content)\b", val):
                    self.requires.add("intrinsic-size-keyword")
            if k == "aspect-ratio":
                self.requires.add("aspect-ratio")
            if k.startswith("overflow"):
                self.requires.add("overflow")
            if k == "box-sizing" and val == "border-box":
                pass
            style[camel(k)] = val
        return style

    def text_measure(self, el, text):
        size, fam, lh = self.page.font(el)
        if not fam or "ahem" not in fam.lower():
            raise Skip("non-Ahem text")
        if lh in ("1", "normal", "%spx" % fmt(size), "100%"):
            line = size
        else:
            p = to_px(lh, size)
            if isinstance(p, (int, float)):
                line = p
            elif re.match(r"^\d*\.?\d+$", lh):
                line = float(lh) * size
            else:
                raise Skip("line-height " + lh)
        return {"text": text, "charWidth": fmt(size), "lineHeight": fmt(line)}

    def build(self, el, parent_display, ancestors):
        """Return (node, expected) for element el."""
        is_root = not ancestors
        if el.tag in REPLACED:
            raise Skip("replaced element <%s>" % el.tag)
        style = self.style_for(el, parent_display, is_root)
        node = {"style": dict(style)}
        exp = {}
        disp = style["display"]
        kids = []
        texts = []
        for c in el.children:
            if isinstance(c, El):
                if c.tag in IGNORED_TAGS:
                    continue
                kids.append(c)
            elif c.strip():
                texts.append(re.sub(r"\s+", " ", c.strip()))
        if texts and kids:
            if disp not in ("flex", "inline-flex"):
                raise Skip("mixed inline content")
        if texts and not kids:
            node["measure"] = self.text_measure(el, " ".join(texts))
            self.requires.add("measure")
        child_nodes, child_exp = [], []
        if kids or (texts and kids):
            for c in el.children:
                if isinstance(c, El):
                    if c.tag in IGNORED_TAGS:
                        continue
                    n, e = self.build(c, disp, ancestors + [el])
                    child_nodes.append(n)
                    child_exp.append(e)
                elif c.strip():
                    # Anonymous flex item wrapping a text run.
                    m = self.text_measure(el, re.sub(r"\s+", " ", c.strip()))
                    child_nodes.append({"style": {"display": "block"}, "measure": m,
                                        "anonymous": True})
                    child_exp.append({})
                    self.requires.add("measure")
            if disp not in ("flex", "inline-flex", "none") and child_nodes:
                self.requires.add("block-layout")
        if child_nodes:
            node["children"] = child_nodes
            exp["children"] = child_exp
        # Expectations (only for elements checkLayout actually checks)
        a = el.attrs if id(el) in self.checked else {}
        if "data-expected-width" in a:
            exp["width"] = float_or_skip(a["data-expected-width"])
            self.checks += 1
        if "data-expected-height" in a:
            exp["height"] = float_or_skip(a["data-expected-height"])
            self.checks += 1
        if "data-offset-x" in a or "data-offset-y" in a:
            self.offsets(el, ancestors, exp)
        for k in a:
            if k.startswith("data-expected-") and k not in ("data-expected-width", "data-expected-height"):
                self.dropped += 1
            if k.startswith("data-total-"):
                self.dropped += 1
        return node, exp

    def offsets(self, el, ancestors, exp):
        # offsetParent: nearest positioned ancestor (or body). Only usable if
        # it lies inside the case's tree.
        k = 0
        op = None
        for depth, anc in enumerate(reversed(ancestors), start=1):
            if self.position(anc) != "static":
                op, k = anc, depth
                break
        if op is None or self.position(el) == "fixed":
            n = (1 if "data-offset-x" in el.attrs else 0) + (1 if "data-offset-y" in el.attrs else 0)
            self.dropped += n
            return
        d = self.page.declared(op)
        fs = self.page.font(op)[0]
        bl = to_px(d.get("border-left-width", "0"), fs) or 0
        bt = to_px(d.get("border-top-width", "0"), fs) or 0
        if isinstance(bl, str) or isinstance(bt, str):
            raise Skip("percentage border")
        if "data-offset-x" in el.attrs:
            exp["x"] = fmt(float_or_skip(el.attrs["data-offset-x"]) + bl)
            self.checks += 1
        if "data-offset-y" in el.attrs:
            exp["y"] = fmt(float_or_skip(el.attrs["data-offset-y"]) + bt)
            self.checks += 1
        if k != 1:
            exp["relativeTo"] = k

    def available_for_root(self, root):
        # Walk up to body: every ancestor must be a plain block without
        # padding/border/explicit width, or give a definite width.
        n = root.parent
        while n is not None and n.tag not in ("body", "#document", "html"):
            d = self.page.declared(n)
            if "float" in d and d["float"] != "none":
                raise Skip("root inside float")
            if self.display(n) != "block":
                raise Skip("root inside non-block ancestor")
            if "width" in d:
                w = to_px(d["width"], self.page.font(n)[0])
                if not isinstance(w, (int, float)):
                    raise Skip("ancestor width " + d["width"])
                if d.get("box-sizing") == "border-box":
                    for s in ("left", "right"):
                        w -= (to_px(d.get("padding-" + s, "0"), 16) or 0) + \
                             (to_px(d.get("border-%s-width" % s, "0"), 16) or 0)
                return {"width": fmt(w), "height": None}
            for s in ("left", "right"):
                for p in ("padding-" + s, "border-%s-width" % s, "margin-" + s):
                    if p in d and to_px(d[p], 16) not in (0, None):
                        raise Skip("ancestor inline insets")
            n = n.parent
        if n is not None and n.tag == "body":
            d = self.page.declared(n)
            if any(k.startswith(("margin", "padding", "width", "border")) for k in d):
                raise Skip("body box styled")
        return {"width": VIEWPORT_CONTENT_WIDTH, "height": None}


def float_or_skip(v):
    try:
        return fmt(float(v))
    except ValueError:
        raise Skip("non-numeric expectation")


def is_ancestor(a, b):
    n = b.parent
    while n is not None:
        if n is a:
            return True
        n = n.parent
    return False


def convert_file(path, rel, commit):
    page = Page(path)
    sels = find_check_calls(page)
    selected = []
    for s in sels:
        selected.extend(select_all(page, s))
    if not selected:
        raise Skip("selector matched nothing")
    # checkLayout checks each matched node and all its descendants.
    checked = []
    def collect(el):
        checked.append(el)
        for c in el.element_children():
            collect(c)
    for el in selected:
        collect(el)
    probe = Converter(page)
    candidates = []
    for el in checked:
        a = el.attrs
        if not any(k in a for k in ("data-expected-width", "data-expected-height",
                                    "data-offset-x", "data-offset-y")):
            continue
        root = el
        if "data-offset-x" in a or "data-offset-y" in a:
            n = el.parent
            top = el
            found = False
            while n is not None and n.tag not in ("body", "#document", "html"):
                if probe.position(n) != "static":
                    root = n
                    found = True
                    break
                top = n
                n = n.parent
            if not found:
                # offsetParent is <body>: offsets are unusable, but sizes
                # still need the element's real formatting context.
                root = top
        elif el.parent is not None and probe.display(el.parent) not in ("block",):
            n = el
            while n.parent is not None and n.parent.tag not in ("body", "#document", "html"):
                n = n.parent
            root = n
        candidates.append(root)
    roots = []
    for r in candidates:
        if r in roots or any(is_ancestor(o, r) for o in candidates if o is not r):
            continue
        roots.append(r)
    if not roots:
        raise Skip("no checks")
    checked_ids = set(id(e) for e in checked)
    cases = []
    for i, root in enumerate(roots):
        conv = Converter(page)
        conv.checked = checked_ids
        tree, exp = conv.build(root, conv.display(root.parent) if root.parent else "block", [])
        exp.pop("x", None)
        exp.pop("y", None)
        exp.pop("relativeTo", None)
        if conv.checks == 0:
            continue
        case = {
            "id": "wpt/%s%s" % (rel[:-5], "" if len(roots) == 1 else "/%d" % i),
            "source": {
                "suite": "wpt",
                "file": rel,
                "commit": commit,
                "license": "BSD-3-Clause",
                "copyright": "web-platform-tests contributors",
            },
            "direction": conv.direction,
            "tolerance": 0.999,
            "available": conv.available_for_root(root),
            "root": tree,
            "expected": exp,
        }
        if tree["style"].get("display") == "inline-flex" or \
                tree["style"].get("position") in ("absolute", "fixed"):
            conv.root_sizing = "fit-content"
        if conv.root_sizing:
            case["rootSizing"] = conv.root_sizing
        if conv.requires:
            case["requires"] = sorted(conv.requires)
        if conv.dropped:
            case["droppedChecks"] = conv.dropped
        cases.append(case)
    if not cases:
        raise Skip("no checks inside translatable subtree")
    return cases


def main():
    wpt, out_dir = sys.argv[1], sys.argv[2]
    sub = sys.argv[3] if len(sys.argv) > 3 else "css/css-flexbox"
    commit = subprocess.run(["git", "-C", wpt, "rev-parse", "HEAD"],
                            capture_output=True, text=True, check=True).stdout.strip()
    base = os.path.join(wpt, sub)
    skips = collections.Counter()
    written = files = 0
    for dirpath, _, fnames in os.walk(base):
        for fn in sorted(fnames):
            if not fn.endswith(".html") or "-ref" in fn or fn.endswith("-ref.html"):
                continue
            path = os.path.join(dirpath, fn)
            with open(path, encoding="utf-8", errors="replace") as f:
                if "check-layout-th.js" not in f.read():
                    continue
            rel = os.path.relpath(path, wpt)
            try:
                cases = convert_file(path, rel, commit)
            except Skip as e:
                skips[str(e).split(" ")[0] if str(e).startswith(("selector", "pseudo", "unit", "at-rule", "ancestor width", "line-height")) else str(e)] += 1
                continue
            except RecursionError:
                skips["recursion"] += 1
                continue
            files += 1
            for c in cases:
                p = os.path.join(out_dir, c["id"][len("wpt/"):] + ".json")
                os.makedirs(os.path.dirname(p), exist_ok=True)
                with open(p, "w") as f:
                    json.dump(c, f, indent=1)
                    f.write("\n")
                written += 1
    print("wpt: wrote %d cases from %d files (%s)" % (written, files, commit[:12]))
    print("wpt: skipped %d files:" % sum(skips.values()))
    for reason, n in skips.most_common():
        print("  %4d  %s" % (n, reason))


if __name__ == "__main__":
    main()
