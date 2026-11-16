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
WPT_ROOT = "."
SUITE = "wpt"
DEFAULT_FONT_SIZE = 16

VISUAL_PROPS = re.compile(
    r"^(background.*|color|outline.*|box-shadow|cursor|opacity|z-index|"
    r"border(-(top|right|bottom|left))?-color|border.*radius|font-family|"
    r"font-weight|font-style|text-decoration.*|list-style.*|transition.*|"
    r"animation.*|content|visibility|-webkit-.*|will-change|caret-color|"
    r"text-shadow|filter|scrollbar.*|forced-color-adjust|vertical-align|"
    r"text-align|unicode-bidi|"
    r"border-collapse|border-spacing|font-variant.*|letter-spacing|"
    r"word-spacing|tab-size|hyphens|quotes|counter-.*|resize|user-select|"
    r"pointer-events|mix-blend-mode|isolation|clip-path|mask.*|"
    r"backface-visibility|perspective.*|image-rendering|appearance|"
    r"-moz-.*|print-color-adjust)$")
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
CONTAINERS = ("flex", "inline-flex", "grid", "inline-grid")

_ALIGN = {"normal", "stretch", "center", "start", "end", "flex-start",
          "flex-end", "self-start", "self-end", "baseline", "first baseline",
          "last baseline", "left", "right", "safe center", "unsafe center",
          "safe end", "unsafe end", "safe flex-end", "unsafe flex-end",
          "safe start", "safe flex-start", "unsafe start", "unsafe flex-start",
          "space-between", "space-around", "space-evenly", "anchor-center"}
VALID_KEYWORDS = {
    "flex-direction": {"row", "row-reverse", "column", "column-reverse"},
    "flex-wrap": {"nowrap", "wrap", "wrap-reverse"},
    "position": {"static", "relative", "absolute", "fixed", "sticky"},
    "box-sizing": {"content-box", "border-box"},
    "justify-content": _ALIGN - {"baseline", "first baseline", "last baseline", "self-start", "self-end"},
    "align-content": _ALIGN - {"self-start", "self-end", "left", "right", "anchor-center"},
    "align-items": (_ALIGN | {"anchor-center"}) - {"space-between", "space-around", "space-evenly", "auto", "left", "right"},
    "align-self": (_ALIGN | {"auto"}) - {"space-between", "space-around", "space-evenly", "left", "right"},
}


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

LEN_RE = re.compile(r"^([-+]?\d*\.?\d+)(px|em|%)?$")


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


def split_tokens(v):
    """Whitespace-split a CSS value, keeping (...) groups such as calc()
    and minmax() whole."""
    out, depth, cur = [], 0, ""
    for ch in v.strip():
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch.isspace() and depth == 0:
            if cur:
                out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur:
        out.append(cur)
    return out


def box4(v):
    t = split_tokens(v)
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
        elif k in ("grid", "grid-template"):
            out.update(expand_grid_shorthand(k, v))
        elif k in ("grid-row-gap", "grid-column-gap"):
            out[k[len("grid-"):]] = v
        elif k in ("gap", "grid-gap"):
            t = split_tokens(v)
            out["row-gap"] = t[0]
            out["column-gap"] = t[1] if len(t) > 1 else t[0]
        elif k == "flex":
            fx = expand_flex(v)
            if fx is not None:
                out.update(fx)
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
    v = v.strip()
    if v == "none":
        return {"flex-grow": "0", "flex-shrink": "0", "flex-basis": "auto"}
    if v == "auto":
        return {"flex-grow": "1", "flex-shrink": "1", "flex-basis": "auto"}
    if v == "initial":
        return {"flex-grow": "0", "flex-shrink": "1", "flex-basis": "auto"}
    num = re.compile(r"^\d*\.?\d+$")
    toks = v.split()
    kinds = "".join("n" if num.match(t) else "b" for t in toks)
    # Grammar: [<grow> <shrink>?] || <basis>: the numbers must be adjacent,
    # with at most two of them and one basis. Invalid -> declaration dropped.
    if kinds not in ("n", "b", "nn", "nb", "bn", "nnb", "bnn"):
        return None
    nums = [t for t in toks if num.match(t)]
    bas = [t for t in toks if not num.match(t)]
    if bas and not re.match(r"^(\d*\.?\d+(px|%|em)|auto|content|min-content|"
                            r"max-content|fit-content|calc\(.*\))$", bas[0]):
        return None
    if not nums:
        return {"flex-grow": "1", "flex-shrink": "1", "flex-basis": bas[0]}
    return {"flex-grow": nums[0], "flex-shrink": nums[1] if len(nums) > 1 else "1",
            "flex-basis": bas[0] if bas else "0%"}


def expand_grid_shorthand(k, v):
    """grid / grid-template -> longhands. Forms with area strings or line
    names are passed through for the engine (and tagged by grid_requires)."""
    v = v.strip()
    reset = {"grid-template-rows": "none", "grid-template-columns": "none",
             "grid-template-areas": "none"}
    if k == "grid":
        reset.update({"grid-auto-rows": "auto", "grid-auto-columns": "auto",
                      "grid-auto-flow": "row"})
    if v == "none":
        return reset
    if '"' in v or "[" in v or "/" not in v:
        return {k: v}           # complex form: leave to the engine
    rows, cols = [x.strip() for x in v.split("/", 1)]
    out = dict(reset)
    if k == "grid" and "auto-flow" in rows:
        dense = " dense" if "dense" in rows else ""
        out["grid-auto-flow"] = "row" + dense
        auto = re.sub(r"\b(auto-flow|dense)\b", "", rows).strip()
        if auto:
            out["grid-auto-rows"] = auto
        out["grid-template-columns"] = cols
    elif k == "grid" and "auto-flow" in cols:
        dense = " dense" if "dense" in cols else ""
        out["grid-auto-flow"] = "column" + dense
        auto = re.sub(r"\b(auto-flow|dense)\b", "", cols).strip()
        if auto:
            out["grid-auto-columns"] = auto
        out["grid-template-rows"] = rows
    else:
        out["grid-template-rows"] = rows
        out["grid-template-columns"] = cols
    return out


def inline_text(nodes):
    """Text content of inline children, with each <br> as a newline
    (a forced line break for the Ahem measurer) and white space collapsed."""
    parts = []
    for c in nodes:
        if isinstance(c, El):
            if c.tag == "br":
                parts.append("\x00")
        else:
            parts.append(re.sub(r"\s+", " ", c))
    lines = [l.strip(" ") for l in "".join(parts).split("\x00")]
    return "\n".join(lines)


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
        sheets = []
        for el in self.walk(b.doc):
            if el.tag == "link" and "stylesheet" in (el.attrs.get("rel") or "").lower():
                href = el.attrs.get("href") or ""
                if href.startswith("/"):
                    cand = os.path.join(WPT_ROOT, href.lstrip("/"))
                else:
                    cand = os.path.join(os.path.dirname(path), href)
                if not os.path.exists(cand):
                    raise Skip("missing stylesheet")
                with open(cand, encoding="utf-8", errors="replace") as f:
                    sheets.append(f.read())
        for css in sheets + b.styles:
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
        self.area_names = set()
        for _, _, _, decls in self.rules:
            for k, v, _ in decls:
                if k in ("grid-template-areas", "grid-template", "grid"):
                    for q in re.findall(r'"([^"]*)"', v):
                        self.area_names.update(t for t in q.split() if t != ".")
        for m in re.finditer(r'grid-template-areas\s*:\s*((?:"[^"]*"\s*)+)', self.src):
            for q in re.findall(r'"([^"]*)"', m.group(1)):
                self.area_names.update(t for t in q.split() if t != ".")

    @staticmethod
    def walk(el):
        for c in el.element_children():
            yield c
            yield from Page.walk(c)

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
        self.sized_by_ancestor = False
        self.page_offsets = []          # (expected dict, page x, page y)
        self.outside_positioned = False # a positioned ancestor above the root
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
        if parent_display in CONTAINERS and disp in ("inline", "inline-block"):
            disp = "block"   # flex items are blockified
        if "grid-lanes" in disp:
            self.requires.add("grid-lanes")
        elif disp in ("inline-flex", "inline-grid"):
            self.requires.add("display-" + disp)
        elif disp not in ("flex", "grid", "none", "block"):
            self.requires.add("display-" + disp)
        style["display"] = disp
        style["boxSizing"] = "content-box"   # Trellis defaults to border-box
        # Per-axis overflow: Trellis has a single `overflow`, so cases whose
        # axes differ can't be expressed faithfully.
        ox = oy = d.get("overflow", "visible").split()[0] if d.get("overflow") else "visible"
        if d.get("overflow") and len(d["overflow"].split()) == 2:
            oy = d["overflow"].split()[1]
        ox = d.get("overflow-x", ox).strip()
        oy = d.get("overflow-y", oy).strip()
        if ox != oy:
            self.requires.add("overflow-axis")
        for k, v in d.items():
            v = v.strip()
            if k == "flex-wrap" and v == "balance":
                self.requires.add("flex-wrap-balance")   # css-flexbox-2
                style["flexWrap"] = v
                continue
            if k in ("clear",):
                continue            # no effect on flex layout
            if k in ("overflow-x", "overflow-y"):
                if v in ("visible",):
                    continue
                k = "overflow"
            if k in VALID_KEYWORDS and v not in VALID_KEYWORDS[k]:
                continue            # invalid CSS: the browser drops it
            if k in ("flex-grow", "flex-shrink") and not re.match(r"^\d*\.?\d+$", v):
                continue
            if k in ("display", "font", "font-size", "line-height", "white-space",
                     "word-break", "overflow-wrap", "word-wrap"):
                continue
            if VISUAL_PROPS.match(k):
                continue
            if k in SKIP_PROPS:
                raise Skip(SKIP_PROPS[k])
            if k == "position" and v == "sticky":
                self.requires.add("position-sticky")
            if k == "direction":
                if not is_root:
                    raise Skip("direction set below case root")
                self.direction = v.strip()
                continue
            if k == "float":
                if parent_display in CONTAINERS and not is_root:
                    continue        # floats don't apply to flex items
                if is_root:
                    if v.strip() != "none":
                        self.root_sizing = "fit-content"
                    continue
                if v.strip() != "none":
                    raise Skip("float")
                continue
            if k.startswith("grid"):
                self.grid_requires(k, v)
            if re.search(r"(inline|block)", k) and k not in ("display",):
                self.requires.add("logical-properties")
            val = norm_value(v, fs, self.requires)
            if isinstance(val, str):
                if re.search(r"\b(min-content|max-content|fit-content)\b", val) \
                        and not k.startswith("grid"):
                    self.requires.add("intrinsic-size-keyword")
            if k == "aspect-ratio":
                self.requires.add("aspect-ratio")
                m = re.match(r"^(?:auto\s+)?(\d*\.?\d+)\s*/\s*(\d*\.?\d+)$", str(val))
                if m:
                    val = fmt(float(m.group(1)) / float(m.group(2)))
            if k.startswith("overflow"):
                self.requires.add("overflow")
            if k == "box-sizing" and val == "border-box":
                pass
            style[camel(k)] = val
        return style

    PLACEMENT = ("grid-row", "grid-column", "grid-row-start", "grid-row-end",
                 "grid-column-start", "grid-column-end", "grid-area")

    def grid_requires(self, k, v):
        if "subgrid" in v:
            self.requires.add("subgrid")
        if "masonry" in v:
            self.requires.add("masonry")
        if k in ("grid", "grid-template") and '"' in v:
            self.requires.add("grid-template-shorthand")
        if k in ("grid-template-columns", "grid-template-rows", "grid-template",
                 "grid") and "[" in v:
            self.requires.add("grid-named-lines")
        if k in self.PLACEMENT:
            for tok in re.split(r"[\s/]+", v.strip()):
                if not tok or tok in ("span", "auto") or re.match(r"^-?\d+$", tok):
                    continue
                base = re.sub(r"-(start|end)$", "", tok)
                if tok not in self.page.area_names and base not in self.page.area_names:
                    self.requires.add("grid-named-lines")

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
        m = {"text": text, "charWidth": fmt(size), "lineHeight": fmt(line)}
        ws = self.inherited(el, "white-space")
        if ws in ("nowrap", "pre"):
            m["nowrap"] = True
        elif ws not in (None, "normal"):
            raise Skip("white-space " + ws)
        for prop in ("word-break", "overflow-wrap", "word-wrap"):
            if self.inherited(el, prop) not in (None, "normal"):
                raise Skip(prop)
        return m

    def inherited(self, el, prop):
        n = el
        while isinstance(n, El) and not n.tag.startswith("#"):
            d = self.page.declared(n)
            if prop in d:
                return d[prop].strip()
            n = n.parent
        return None

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
                texts.append(c)
        if texts and kids:
            if disp not in CONTAINERS:
                raise Skip("mixed inline content")
        if texts and not kids:
            node["measure"] = self.text_measure(el, inline_text(el.children))
            self.requires.add("measure")
        child_nodes, child_exp = [], []
        if kids or (texts and kids):
            run = []        # text and <br> forming one anonymous item

            def flush():
                if any(isinstance(x, str) and x.strip() for x in run):
                    m = self.text_measure(el, inline_text(run))
                    child_nodes.append({"style": {"display": "block"}, "measure": m,
                                        "anonymous": True})
                    child_exp.append({})
                    self.requires.add("measure")
                del run[:]
            for c in el.children:
                if isinstance(c, El) and c.tag == "br":
                    run.append(c)
                elif isinstance(c, El):
                    if c.tag in IGNORED_TAGS:
                        continue
                    flush()
                    if self.position(c) in ("absolute", "fixed") and self.position(el) == "static":
                        # CSS: the containing block is a positioned ancestor
                        # further up; Trellis always uses the parent's padding box.
                        self.requires.add("abspos-ancestor-cb")
                    n, e = self.build(c, disp, ancestors + [el])
                    child_nodes.append(n)
                    child_exp.append(e)
                else:
                    run.append(c)
            flush()
            if disp not in CONTAINERS + ("none",) and child_nodes:
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
        n = (1 if "data-offset-x" in el.attrs else 0) + (1 if "data-offset-y" in el.attrs else 0)
        if op is None and self.position(el) != "fixed" and not self.outside_positioned \
                and not any(self.display(a) == "none" for a in ancestors + [el]):
            # offsetParent is <body>: a page position. Kept for anchor-relative
            # checks (dx/dy), which don't depend on where the root sits.
            ox = float_or_skip(el.attrs["data-offset-x"]) if "data-offset-x" in el.attrs else None
            oy = float_or_skip(el.attrs["data-offset-y"]) if "data-offset-y" in el.attrs else None
            self.page_offsets.append((exp, ox, oy))
            return
        if op is None or self.position(el) == "fixed":
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

    def resolve_page_offsets(self, exp_root):
        """Turn page offsets (offsetParent = body) into dx/dy relative to an
        anchor node: the first with both offsets. Returns the anchor's child
        index path, or None."""
        anchor = next(((e, x, y) for e, x, y in self.page_offsets
                       if x is not None and y is not None), None)
        if anchor is None:
            for _, x, y in self.page_offsets:
                self.dropped += (x is not None) + (y is not None)
            return None

        def path_to(node, target, path):
            if node is target:
                return path
            for i, c in enumerate(node.get("children", [])):
                r = path_to(c, target, path + [i])
                if r is not None:
                    return r
            return None
        ae, ax, ay = anchor
        self.dropped += 2           # the anchor's own offsets are trivially 0
        for e, x, y in self.page_offsets:
            if e is ae:
                continue
            if x is not None:
                e["dx"] = fmt(x - ax)
                self.checks += 1
            if y is not None:
                e["dy"] = fmt(y - ay)
                self.checks += 1
        return path_to(exp_root, ae, [])

    def available_height_for_root(self, root):
        """The parent's definite content height, when the root's own height
        constraints are percentages that resolve against it. (A given
        available height is laid out exactly, so it's only passed when the
        root sizes itself from it.)"""
        d = self.page.declared(root)
        if not any("%" in d.get(k, "") for k in ("height", "min-height", "max-height")):
            return None
        p = root.parent
        if p is None or p.tag in ("body", "html", "#document"):
            return None
        pd = self.page.declared(p)
        h = to_px(pd.get("height", "auto"), self.page.font(p)[0])
        if not isinstance(h, (int, float)):
            return None
        if pd.get("box-sizing") == "border-box":
            for s in ("top", "bottom"):
                h -= (to_px(pd.get("padding-" + s, "0"), 16) or 0) + \
                     (to_px(pd.get("border-%s-width" % s, "0"), 16) or 0)
        return fmt(h)

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
                self.sized_by_ancestor = True   # an explicitly narrow container
                return {"width": fmt(w), "height": None}
            for s in ("left", "right"):
                for p in ("padding-" + s, "border-%s-width" % s, "margin-" + s):
                    if p in d and to_px(d[p], 16) not in (0, None):
                        raise Skip("ancestor inline insets")
            n = n.parent
        if n is not None and n.tag == "body":
            d = self.page.declared(n)
            if "width" in d:
                raise Skip("body box styled")
            # Viewport is 800px; body's UA margin is 8px each side.
            w = 800.0
            for side in ("left", "right"):
                for prop, default in (("margin-" + side, "8px"), ("padding-" + side, "0"),
                                      ("border-%s-width" % side, "0")):
                    px = to_px(d.get(prop, default), 16)
                    if not isinstance(px, (int, float)):
                        raise Skip("body box styled")
                    w -= px
            return {"width": fmt(w), "height": None}
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
    root_skips = []
    for i, root in enumerate(roots):
        conv = Converter(page)
        conv.checked = checked_ids
        n = root.parent
        while n is not None and n.tag not in ("body", "html", "#document"):
            if conv.position(n) != "static":
                conv.outside_positioned = True
            n = n.parent
        try:
            tree, exp = conv.build(root, conv.display(root.parent) if root.parent else "block", [])
            avail = conv.available_for_root(root)
            ah = conv.available_height_for_root(root)
            if ah is not None:
                avail = dict(avail, height=ah)
        except Skip as e:
            root_skips.append(str(e))
            continue
        anchor_path = conv.resolve_page_offsets(exp)
        exp.pop("x", None)
        exp.pop("y", None)
        exp.pop("relativeTo", None)
        if conv.checks == 0:
            continue
        case = {
            "id": "%s/%s%s" % (SUITE, rel[:-5], "" if len(roots) == 1 else "/%d" % i),
            "source": {
                "suite": SUITE,
                "file": rel,
                "commit": commit,
                "license": "BSD-3-Clause",
                "copyright": "web-platform-tests contributors",
            },
            "direction": conv.direction,
            "tolerance": 0.999,
            "pixelScale": 0,
            "available": avail,
            "root": tree,
            "expected": exp,
        }
        if tree["style"].get("display") in ("inline-flex", "inline-grid") or \
                tree["style"].get("position") in ("absolute", "fixed"):
            conv.root_sizing = "fit-content"
        if conv.root_sizing == "fit-content" and conv.sized_by_ancestor:
            # Shrink-to-fit in a narrow container: may size at min-content.
            case.setdefault("requires", []).append("intrinsic-size-keyword")
        if conv.root_sizing == "fit-content":
            # Shrink-to-fit root: trellis-case lays a given available width
            # out exactly, so leave it unconstrained (content size).
            case["available"] = {"width": None, "height": None}
        if anchor_path is not None:
            case["anchor"] = anchor_path
        if conv.requires or case.get("requires"):
            case["requires"] = sorted(set(case.get("requires", [])) | conv.requires)
        if conv.dropped:
            case["droppedChecks"] = conv.dropped
        cases.append(case)
    if not cases:
        raise Skip(root_skips[0] if root_skips else "no checks inside translatable subtree")
    return cases


def main():
    global WPT_ROOT, SUITE
    wpt, out_dir = sys.argv[1], sys.argv[2]
    WPT_ROOT = wpt
    sub = sys.argv[3] if len(sys.argv) > 3 else "css/css-flexbox"
    SUITE = sys.argv[4] if len(sys.argv) > 4 else "wpt"
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
                p = os.path.join(out_dir, c["id"][len(SUITE) + 1:] + ".json")
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
