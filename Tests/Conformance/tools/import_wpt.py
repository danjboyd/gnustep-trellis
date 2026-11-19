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
  * css-grid/alignment's support/style-change.js tests (evaluateStyleChange
    and evaluateStyleChangeMultiple around inline el.style.prop = "value"
    changes) import one case per phase, ids ending /before and /after, each
    in the state its checkLayout sees.
"""
import collections
import html.parser
import json
import os
import re
import subprocess
import sys

VIEWPORT_CONTENT_WIDTH = 784
VIEWPORT = (800, 600)             # WPT's viewport: the initial containing block
WPT_ROOT = "."
SUITE = "wpt"
DEFAULT_FONT_SIZE = 16
# The root element's font size, for rem. Page() sets it for the page being
# converted (pages are converted one at a time).
ROOT_FONT_SIZE = DEFAULT_FONT_SIZE
# CSS absolute units in px (CSS Values 4: 1in = 96px = 2.54cm).
ABS_UNITS = {"in": 96.0, "cm": 96 / 2.54, "mm": 96 / 25.4, "q": 96 / 101.6,
             "pt": 96 / 72, "pc": 16.0}

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

    HEAD_ONLY = {"html", "head", "meta", "link", "title", "base", "style", "script", "noscript"}

    def handle_starttag(self, tag, attrs):
        if self.body is None and tag not in self.HEAD_ONLY and tag != "body" \
                and self.cur.tag in ("#document", "html", "head"):
            # HTML implies <body> before the first element that can't be
            # in <head>, so "body > div" matches pages that omit the tag.
            if self.cur.tag == "head":
                self.cur = self.cur.parent
            self.handle_starttag("body", [])
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


AHEM_IMPORT_RE = re.compile(r"""@import\s+(?:url\()?\s*["']?/fonts/ahem\.css["']?\s*\)?\s*;""", re.I)


def nest_selector(parent, child):
    """A nested rule's selector (CSS Nesting): & is the parent; without &,
    the child is a descendant (or a relative > + ~ selector) of it."""
    out = []
    for p in split_selector_list(parent):
        for c in split_selector_list(child):
            out.append(c.replace("&", p) if "&" in c else p + " " + c)
    return ", ".join(out)


def split_selector_list(sel):
    """Split a selector list at top-level commas (not inside :not(...))."""
    parts, depth, cur = [], 0, ""
    for ch in sel:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur.strip())
    return parts


def parse_stylesheet(css):
    css = strip_comments(css)
    # Cases assume Ahem already, so importing its stylesheet changes nothing.
    # Any other @import still skips the file.
    css = AHEM_IMPORT_RE.sub("", css)
    rules = []

    def block(i, sel):
        """Parse a rule body from css[i] (after its '{') to its '}'. Nested
        rules (CSS Nesting) follow their parent rule. Returns the index
        after the '}'."""
        decls, buf, nested = [], "", []
        while i < len(css):
            ch = css[i]
            if ch == "{":
                head, _, inner = buf.rpartition(";")
                decls.append(head)
                inner = inner.strip()
                if inner.startswith("@"):
                    raise Skip("at-rule " + inner.split()[0])
                sub = []
                i = block_into(i + 1, nest_selector(sel, inner), sub)
                nested.extend(sub)
                buf = ""
                continue
            if ch == "}":
                decls.append(buf)
                rules.append((sel, parse_decls(";".join(decls))))
                rules.extend(nested)
                return i + 1
            buf += ch
            i += 1
        raise Skip("unbalanced stylesheet")

    def block_into(i, sel, out):
        nonlocal rules
        saved, rules = rules, out
        try:
            return block(i, sel)
        finally:
            rules = saved

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
        pos = block(i + 1, sel)
    return rules


COMPOUND_RE = re.compile(r"^(\*|[a-zA-Z][\w-]*)?((?:[.#][\w-]+|\[[\w-]+(?:=(?:\"[^\"]*\"|'[^']*'|[\w-]+))?\])*)((?::[\w-]+(?:\([^)]*\))?)*)$")


def parse_selector(sel):
    """Return list of (combinator, compound) from left to right."""
    # Inside (...) (An+B, :not()), whitespace and + aren't combinators:
    # squeeze them out and hide + until the compounds are split.
    sel = re.sub(r"\(([^)]*)\)",
                 lambda m: "(" + re.sub(r"\s+", "", m.group(1)).replace("+", "\0") + ")",
                 sel.strip())
    sel = re.sub(r"\s*>\s*", " > ", sel)
    sel = re.sub(r"\s*\+\s*", " + ", sel)
    sel = re.sub(r"\s*~\s*", " ~ ", sel)
    toks = [t.replace("\0", "+") for t in sel.split()]
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
        attrs = [(a, (v1 or v2 or v3) if eq else None) for a, eq, v1, v2, v3 in
                 re.findall(r"\[([\w-]+)(=(?:\"([^\"]*)\"|'([^']*)'|([\w-]+)))?\]", rest)]
        rest = re.sub(r"\[[^\]]*\]", "", rest)
        classes = set(re.findall(r"\.([\w-]+)", rest))
        ids = re.findall(r"#([\w-]+)", rest)
        pseudo = re.findall(r":([\w-]+(?:\([^)]*\))?)", pseudos)
        for p in pseudo:
            m = NTH_RE.match(p)
            if m:
                if parse_an_b(m.group(2)) is None:
                    raise Skip("pseudo :" + p)
            elif not re.match(r"^(first-child|last-child|first-of-type|last-of-type|only-child|only-of-type|not\(\.[\w-]+\))$", p):
                raise Skip("pseudo :" + p)
        parts.append((comb or " ", {"tag": None if tag in (None, "*") else tag.lower(),
                                     "classes": classes, "ids": ids, "pseudo": pseudo,
                                     "attrs": attrs}))
        comb = None
    return parts


DYNAMIC_PSEUDO_RE = re.compile(r":(hover|active|focus|focus-within|focus-visible|visited)(?![\w-])")
NTH_RE = re.compile(r"^(nth-child|nth-last-child|nth-of-type|nth-last-of-type)\((.*)\)$")


def parse_an_b(arg):
    """Parse an An+B argument (odd, even, 3, 2n, -n+3, 2n + 1, ...) into
    (a, b), or None if it isn't one (e.g. the 'of S' form)."""
    t = re.sub(r"\s+", "", arg.strip().lower())
    if t == "odd":
        return (2, 1)
    if t == "even":
        return (2, 0)
    m = re.match(r"^([-+]?\d+)$", t)
    if m:
        return (0, int(m.group(1)))
    m = re.match(r"^([-+]?)(\d*)n([-+]\d+)?$", t)
    if not m:
        return None
    a = int(m.group(2)) if m.group(2) else 1
    if m.group(1) == "-":
        a = -a
    return (a, int(m.group(3)) if m.group(3) else 0)


def an_b_matches(a, b, idx):
    """True if idx (1-based) is a*n + b for some integer n >= 0."""
    if a == 0:
        return idx == b
    n, r = divmod(idx - b, a)
    return r == 0 and n >= 0


def specificity(parts):
    a = b = c = 0
    for _, comp in parts:
        a += len(comp["ids"])
        b += len(comp["classes"]) + len(comp["pseudo"]) + len(comp.get("attrs", []))
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
    for a, v in comp.get("attrs", []):
        if a not in el.attrs or (v is not None and el.attrs.get(a) != v):
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
        if p == "only-of-type" and len(typed) != 1:
            return False
        m = NTH_RE.match(p)
        if m:
            a, b = parse_an_b(m.group(2))
            pos = {"nth-child": idx, "nth-last-child": len(sib) - idx + 1,
                   "nth-of-type": tidx, "nth-last-of-type": len(typed) - tidx + 1}[m.group(1)]
            if not an_b_matches(a, b, pos):
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


FIXED_UNIT_RE = re.compile(r"(?<![\w.-])([-+]?\d*\.?\d+)(rem|in|cm|mm|q|pt|pc)\b",
                           re.IGNORECASE)


def fixed_units_to_px(v):
    """Rewrite rem and absolute lengths (in, cm, mm, Q, pt, pc) as px.
    They don't depend on the element, so they translate exactly."""
    def repl(m):
        n, unit = float(m.group(1)), m.group(2).lower()
        n *= ROOT_FONT_SIZE if unit == "rem" else ABS_UNITS[unit]
        return "%spx" % fmt(n)
    return FIXED_UNIT_RE.sub(repl, v)


def to_px(v, font_size):
    """Convert a single length token. Returns number (px), '<n>%' or None."""
    v = fixed_units_to_px(v.strip())
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
    v = fixed_units_to_px(re.sub(r"\s+", " ", v.strip()))
    # CSS math functions; the lookbehind keeps minmax() (a grid track
    # function, supported) from matching max(.
    if re.search(r"(?<![\w-])calc\(", v):
        requires.add("css-calc")
    if re.search(r"(?<![\w-])(min|max|clamp)\(", v):
        requires.add("css-min-max")
    if re.search(r"\d(vw|vh|vmin|vmax|ch|ex|lh|rlh|cqw|cqh|cqi|cqb|cqmin|cqmax)\b", v, re.IGNORECASE):
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


GRID_PLACEMENT = ("grid-row", "grid-column", "grid-row-start", "grid-row-end",
                  "grid-column-start", "grid-column-end", "grid-area")


def valid_grid_line(v):
    """CSS Grid <grid-line>: auto | <custom-ident> |
    [<integer> && <custom-ident>?] | [span && [<integer> || <custom-ident>]]."""
    toks = v.split()
    if toks == ["auto"]:
        return True
    span = ints = idents = 0
    for t in toks:
        if t == "span":
            span += 1
        elif re.match(r"^[-+]?\d+$", t):
            if int(t) == 0 or (span and int(t) < 0):
                return False
            ints += 1
        elif re.match(r"^-?[A-Za-z_][\w-]*$", t) and t not in ("auto", "span"):
            idents += 1
        else:
            return False
    if span > 1 or ints > 1 or idents > 1 or not toks:
        return False
    if span and not (ints or idents):
        return False
    if span and ints and int(next(t for t in toks if re.match(r"^[-+]?\d+$", t))) < 0:
        return False
    return True


def valid_grid_placement(k, v):
    parts = [x.strip() for x in v.split("/")]
    most = {"grid-area": 4, "grid-row": 2, "grid-column": 2}.get(k, 1)
    return len(parts) <= most and all(valid_grid_line(x) for x in parts)


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
        elif k in GRID_PLACEMENT and not valid_grid_placement(k, v):
            continue    # an invalid declaration is ignored
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
    # A unitless zero right after two flex factors is the basis ("1 0 0" is
    # grow 1, shrink 0, basis 0; css-flexbox-1 7.2), not a third number.
    for i, t in enumerate(toks):
        if i >= 2 and num.match(t) and float(t) == 0 and all(num.match(x) for x in toks[i - 2:i]):
            toks[i] = "0px"
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
    """grid / grid-template -> longhands. Forms with area strings are passed
    through for the engine (and tagged by grid_requires); line names stay
    in the track lists."""
    v = v.strip()
    reset = {"grid-template-rows": "none", "grid-template-columns": "none",
             "grid-template-areas": "none"}
    if k == "grid":
        reset.update({"grid-auto-rows": "auto", "grid-auto-columns": "auto",
                      "grid-auto-flow": "row"})
    if v == "none":
        return reset
    if '"' in v or "/" not in v:
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
                for s in split_selector_list(sel):
                    if DYNAMIC_PSEUDO_RE.search(s):
                        # :hover, :focus... never match in a static page.
                        continue
                    try:
                        parts = parse_selector(s)
                    except Skip:
                        # A rule we can't match only matters if it could hit
                        # the tested subtree; be conservative and skip.
                        raise
                    self.rules.append((parts, specificity(parts), order, decls))
                    order += 1
        self.cache = {}
        # rem: the root element's font size. A rem in the root's own
        # font-size refers to the initial value.
        global ROOT_FONT_SIZE
        ROOT_FONT_SIZE = DEFAULT_FONT_SIZE
        root = next((e for e in b.doc.element_children() if e.tag == "html"), None)
        if root is not None:
            ROOT_FONT_SIZE = self.font(root)[0]
            self.cache = {}

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
        self.y_from_root = False        # a y offset measured from the case root
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
        elif disp == "inline-grid" and (is_root or parent_display in CONTAINERS):
            # A root inline-grid is a grid sized shrink-to-fit (handled with
            # root_sizing), and a flex or grid item is blockified to grid.
            # Only one sitting on a line in a block needs inline formatting.
            pass
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
                if v.strip() not in ("ltr", "rtl"):
                    continue
                if is_root:
                    self.direction = v.strip()
                    continue
                # Below the root: the engine takes direction per node and
                # its descendants inherit it, as in CSS.
                style["direction"] = v.strip()
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
                self.grid_requires(k, v, el)
            if re.search(r"(inline|block)", k) and k not in ("display",):
                self.requires.add("logical-properties")
            val = norm_value(v, fs, self.requires)
            # Trellis takes calc() in lengths, not in grid track lists.
            if k.startswith(("grid-template", "grid-auto")) and "calc(" in str(val):
                self.requires.add("css-calc-tracks")
            if isinstance(val, str):
                if re.search(r"\b(min-content|max-content|fit-content)\b", val) \
                        and not k.startswith("grid"):
                    self.requires.add("intrinsic-size-keyword")
                # The css-sizing-4 'stretch' size keyword (and its prefixed
                # forms); align-*/justify-* 'stretch' is a different thing.
                if re.search(r"(^|\s)(stretch|-webkit-fill-available|-moz-available)(\s|$)", val) \
                        and re.match(r"^(min-|max-)?(width|height)$|^flex-basis$", k):
                    self.requires.add("intrinsic-size-keyword")
            if k == "aspect-ratio":
                self.requires.add("aspect-ratio")
                # "a / b" -> a number; keep a leading "auto" ("auto 2"), which
                # means the ratio applies to the content box (css-sizing-4).
                m = re.match(r"^(auto\s+)?(\d*\.?\d+)(?:\s*/\s*(\d*\.?\d+))?$", str(val))
                if m:
                    r = fmt(float(m.group(2)) / float(m.group(3) or 1))
                    val = ("auto %s" % r) if m.group(1) else r
            if k.startswith("overflow"):
                self.requires.add("overflow")
            if k == "box-sizing" and val == "border-box":
                pass
            style[camel(k)] = val
        if "position" not in style and self.position(el) == "static" \
                and self.has_abspos_descendant(el):
            # Trellis boxes default to relative; say static so an abspos
            # descendant's containing block is found further up, as in CSS.
            # (With no insets, static and relative lay out the same.)
            style["position"] = "static"
        return style

    def has_abspos_descendant(self, el):
        for c in el.children:
            if isinstance(c, El) and c.tag not in IGNORED_TAGS:
                if self.position(c) in ("absolute", "fixed") or self.has_abspos_descendant(c):
                    return True
        return False

    PLACEMENT = GRID_PLACEMENT

    def grid_requires(self, k, v, el=None):
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
                areas = self.parent_areas(el)
                if tok not in areas and base not in areas:
                    self.requires.add("grid-named-lines")

    def parent_areas(self, el):
        """Area names of el's own grid container (not page-wide: another
        grid on the page may define an area with the same name)."""
        p = el.parent if el is not None else None
        if p is None or not isinstance(p, El):
            return set()
        d = self.page.declared(p)
        names = set()
        for k in ("grid-template-areas", "grid-template", "grid"):
            for q in re.findall(r'"([^"]*)"', d.get(k, "")):
                names.update(t for t in q.split() if t != ".")
        return names

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
                    if self.position(el) == "static" and (
                            self.position(c) == "fixed" or
                            (self.position(c) == "absolute" and
                             all(self.position(a) == "static" for a in ancestors + [el]))):
                        # Static ancestors are written as position: static, so
                        # Trellis finds a positioned ancestor further up as CSS
                        # does. Not expressible: fixed (the viewport), or no
                        # positioned ancestor inside the case (the initial
                        # containing block, or one above the case root; Trellis
                        # would use the layout root's padding box).
                        self.requires.add("abspos-ancestor-cb")
                    if self.position(c) == "absolute" and self.position(el) == "static":
                        cb = next((a for a in reversed(ancestors + [el])
                                   if self.position(a) != "static"), None)
                        if cb is not None and "grid" in self.display(cb):
                            # A grid container two or more levels up: its grid
                            # placement and post-min/max size apply to the box.
                            self.requires.add("abspos-grid-descendant")
                    n, e = self.build(c, disp, ancestors + [el])
                    child_nodes.append(n)
                    child_exp.append(e)
                else:
                    run.append(c)
            flush()
            if disp not in CONTAINERS + ("none",) and child_nodes:
                self.requires.add("block-layout")
                if margins_collapse(node["style"], child_nodes, is_root or parent_display in CONTAINERS):
                    self.requires.add("margin-collapse")
                if not self.establishes_bfc(el, node["style"], parent_display, is_root) \
                        and stretch_margin_zeroed(node["style"], child_nodes):
                    self.requires.add("margin-collapse")
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
        if op is ancestors[0] and "data-offset-y" in el.attrs:
            self.y_from_root = True

    def establishes_bfc(self, el, style, parent_display, is_root):
        """Whether a block box is a formatting-context root in CSS (the case
        root counts only when something makes it one)."""
        return parent_display in CONTAINERS \
            or style.get("overflow", "visible") != "visible" \
            or style.get("display") in ("flow-root", "inline-block") \
            or self.position(el) in ("absolute", "fixed") \
            or self.page.declared(el).get("float", "none").strip() != "none" \
            or bool(is_root and self.root_sizing)

    def root_margin_collapses(self, root, tree, exp):
        """The case root is a block in the page, so unless something makes it
        a formatting-context root, its first child's top margin collapses
        through its top edge (moving the child to the root's top) and its
        last child's bottom margin through its bottom edge (out of an auto
        height). Trellis keeps both inside, so this matters only to a y
        offset measured from the root, or a checked auto height."""
        st = tree["style"]
        if st.get("display") != "block" or st.get("overflow", "visible") != "visible" \
                or self.position(root) in ("absolute", "fixed") or self.root_sizing \
                or (root.parent is not None and self.display(root.parent) in CONTAINERS):
            return False
        flow = [c for c in tree.get("children", [])
                if c["style"].get("position") not in ("absolute", "fixed")
                and c["style"].get("display") != "none"]
        if not flow:
            return False
        def through(side, child):
            return not st.get("padding" + side) and not st.get("border%sWidth" % side) \
                and _margin(child["style"], side) > 0
        if self.y_from_root and through("Top", flow[0]):
            return True
        return "height" in exp and st.get("height", "auto") == "auto" \
            and through("Bottom", flow[-1])

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

    def root_containing_block(self, root):
        """An abspos root's containing block size: the nearest positioned
        ancestor's padding box when its size is declared, or the initial
        containing block (the viewport) when there's none. None when the
        size isn't known from the styles."""
        if self.position(root) == "fixed":
            return {"width": VIEWPORT[0], "height": VIEWPORT[1]}
        n = root.parent
        while n is not None and n.tag not in ("html", "#document"):
            if self.position(n) != "static":
                break
            n = n.parent
        if n is None or n.tag in ("html", "#document"):
            return {"width": VIEWPORT[0], "height": VIEWPORT[1]}
        if n.tag == "body":
            return None
        d = self.page.declared(n)
        fs = self.page.font(n)[0]
        out = {}
        for axis, a, b in (("width", "left", "right"), ("height", "top", "bottom")):
            v = to_px(d.get(axis, "auto"), fs)
            if not isinstance(v, (int, float)):
                return None
            pad = [to_px(d.get("padding-" + x, "0"), fs) or 0 for x in (a, b)]
            bor = [to_px(d.get("border-%s-width" % x, "0"), fs) or 0 for x in (a, b)]
            if any(isinstance(x, str) for x in pad + bor):
                return None
            out[axis] = fmt(v - sum(bor) if d.get("box-sizing") == "border-box" else v + sum(pad))
        return out

    def parent_height_definite(self, root):
        p = root.parent
        if p is None or p.tag in ("html", "#document", "body"):
            return False
        return isinstance(to_px(self.page.declared(p).get("height", "auto"),
                                self.page.font(p)[0]), (int, float))

    def available_height_for_root(self, root):
        """The parent's definite content height, when the root's own height
        is a percentage that resolves against it. (A given
        available height is laid out exactly, so it's only passed when the
        root sizes itself from it.)"""
        d = self.page.declared(root)
        if "%" not in d.get("height", "") and not STRETCH_RE.search(d.get("height", "")):
            if any("%" in d.get(k, "") for k in ("min-height", "max-height")) or (
                    any(STRETCH_RE.search(d.get(k, "")) for k in ("min-height", "max-height"))
                    and self.position(root) not in ("absolute", "fixed")
                    and self.parent_height_definite(root)):
                # A % min/max-height with auto height needs the containing
                # block's height without fixing the root's size; the format
                # can't express that (a given available height is exact).
                self.requires.add("containing-block-height")
            return None
        p = root.parent
        if p is None or p.tag in ("html", "#document"):
            return None
        pd = self.page.declared(p)
        if p.tag == "body" and "height" not in pd:
            # An auto-height body: the percentage doesn't resolve.
            return None
        h = to_px(pd.get("height", "auto"), self.page.font(p)[0])
        if not isinstance(h, (int, float)):
            return None
        if STRETCH_RE.search(d.get("height", "")) and self.display(p) == "block" \
                and self.position(root) not in ("absolute", "fixed") \
                and pd.get("overflow", "visible").strip() == "visible" \
                and self.position(p) not in ("absolute", "fixed") \
                and pd.get("float", "none").strip() == "none":
            # CSSWG #11044 (see stretch_margin_zeroed): the parent isn't a
            # BFC, so a root margin on a side without border or padding is
            # treated as 0 when resolving stretch.
            for s in ("top", "bottom"):
                m = to_px(d.get("margin-" + s, "0"), self.page.font(root)[0])
                if m and not to_px(pd.get("padding-" + s, "0"), 16) \
                        and not to_px(pd.get("border-%s-width" % s, "0"), 16):
                    self.requires.add("margin-collapse")
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


def _margin(style, side):
    v = style.get("margin" + side)
    return v if isinstance(v, (int, float)) else 0


def margins_collapse(style, children, own_bfc):
    """True when CSS 2 margin collapsing would change this block's layout.
    Trellis lays a block out as a flex column, whose margins never collapse.
    Adjacent margins of the same sign collapse to the larger (not the sum);
    with opposite signs collapsing is the sum anyway, so those don't count."""
    flow = [c for c in children
            if c["style"].get("position") not in ("absolute", "fixed")
            and c["style"].get("display") != "none"]
    for a, b in zip(flow, flow[1:]):
        x, y = _margin(a["style"], "Bottom"), _margin(b["style"], "Top")
        if x * y > 0:
            return True
    # A first/last child's margin collapses through a parent with no padding
    # or border on that side, unless the parent is a formatting-context root
    # (the case root, a flex or grid item, or overflow other than visible).
    if flow and not own_bfc and style.get("overflow", "visible") == "visible":
        for side, child in (("Top", flow[0]), ("Bottom", flow[-1])):
            if not style.get("padding" + side) and not style.get("border%sWidth" % side) \
                    and _margin(child["style"], side):
                return True
    return False


STRETCH_RE = re.compile(r"(^|\s)(stretch|-webkit-fill-available|-moz-available)(\s|$)")


def stretch_margin_zeroed(style, children):
    """CSSWG #11044: a stretch block size in a parent that isn't a BFC
    treats a margin as 0 where the parent has no border or padding on that
    side (the margin could collapse through), even when it doesn't actually
    collapse. Trellis never collapses, so it keeps the margin."""
    for c in children:
        cs = c["style"]
        if cs.get("position") in ("absolute", "fixed"):
            continue
        if not any(isinstance(cs.get(k), str) and STRETCH_RE.search(cs[k])
                   for k in ("height", "minHeight", "maxHeight")):
            continue
        for side in ("Top", "Bottom"):
            if _margin(cs, side) and not style.get("padding" + side) \
                    and not style.get("border%sWidth" % side):
                return True
    return False


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


# css/css-grid/alignment/support/style-change.js: evaluateStyleChange(el,
# phase, attr, value) adds class `phase` and attribute attr=value to el, then
# runs checkLayout("." + phase); evaluateStyleChangeMultiple(phase, {id:
# {attr: value}}) does the same for several elements. Between phases the
# test changes an inline style (el.style.prop = "value"). Each phase is a
# static layout, so it imports as its own case.
STYLE_CHANGE_ONE = re.compile(
    r"""evaluateStyleChange\(\s*([A-Za-z_]\w*)\s*,\s*(['"])(\w+)\2\s*,\s*(['"])([\w-]+)\4\s*,"""
    r"""\s*(?:(['"])([^'"]*)\6|(-?\d+(?:\.\d+)?))\s*\)\s*;?""")
STYLE_CHANGE_MULTI = re.compile(r"""evaluateStyleChangeMultiple\(\s*(['"])(\w+)\1\s*,\s*""")
STYLE_CHANGE_SET = re.compile(r"""([A-Za-z_]\w*)\.style\.([A-Za-z]+)\s*=\s*(['"])([^'"]*)\3\s*;?""")
STYLE_CHANGE_VAR = re.compile(r"""(?:let|var|const)\s+([A-Za-z_]\w*)\s*=\s*(?=\{)""")
STYLE_CHANGE_NOISE = re.compile(
    r"setup\(\s*\{\s*explicit_done\s*:\s*true\s*\}\s*\)\s*;?|function\s+runTest\s*\(\s*\)\s*\{|"
    r"done\(\s*\)\s*;?|\}|\s+|//[^\n]*")
STYLE_CHANGE_ONLOAD = re.compile(
    r"^\s*(?:document\.fonts\.ready\.then\(\s*\(\s*\)\s*=>\s*\{\s*runTest\(\s*\)\s*;?\s*\}\s*\)|runTest\(\s*\))\s*;?\s*$")


def js_object(code, pos):
    """A {id: {attr: value}} literal at code[pos] as a dict, and the index
    after it; None if it isn't plain data."""
    depth = 0
    for j in range(pos, len(code)):
        if code[j] == "{":
            depth += 1
        elif code[j] == "}":
            depth -= 1
            if depth == 0:
                break
    else:
        return None, pos
    text = code[pos:j + 1]
    text = re.sub(r"'([^'\\]*)'", r'"\1"', text)
    text = re.sub(r"([{,]\s*)([A-Za-z_][\w-]*)\s*:", r'\1"\2":', text)
    text = re.sub(r",(\s*\})", r"\1", text)
    try:
        obj = json.loads(text)
    except ValueError:
        return None, pos
    if not isinstance(obj, dict) or not all(isinstance(v, dict) for v in obj.values()):
        return None, pos
    return obj, j + 1


def style_change_steps(page):
    """The ordered steps of a style-change.js test, or None if the page
    isn't one: ("check", element id, phase, attr, value) and
    ("style", element id, css property, value)."""
    if not any((a.get("src") or "").endswith("support/style-change.js") for a, _ in page.dom.scripts):
        return None
    body = page.dom.body
    onload = body.attrs.get("onload") if body is not None else None
    if onload is None or not STYLE_CHANGE_ONLOAD.match(onload):
        return None
    code = "\n".join(t for a, t in page.dom.scripts if not a.get("src"))
    steps, names, pos = [], {}, 0
    while pos < len(code):
        m = STYLE_CHANGE_NOISE.match(code, pos)
        if m and m.end() > pos:
            pos = m.end()
            continue
        m = STYLE_CHANGE_ONE.match(code, pos)
        if m:
            steps.append(("check", m.group(1), m.group(3), m.group(5),
                          m.group(7) if m.group(6) else m.group(8)))
            pos = m.end()
            continue
        m = STYLE_CHANGE_SET.match(code, pos)
        if m:
            prop = re.sub(r"[A-Z]", lambda c: "-" + c.group(0).lower(), m.group(2))
            steps.append(("style", m.group(1), prop, m.group(4)))
            pos = m.end()
            continue
        m = STYLE_CHANGE_VAR.match(code, pos)
        if m:
            obj, end = js_object(code, m.end())
            if obj is None:
                return None
            names[m.group(1)] = obj
            pos = re.match(r"\s*;?", code[end:]).end() + end
            continue
        m = STYLE_CHANGE_MULTI.match(code, pos)
        if m:
            rest = m.end()
            if code.startswith("{", rest):
                obj, rest = js_object(code, rest)
            else:
                v = re.match(r"([A-Za-z_]\w*)", code[rest:])
                obj = names.get(v.group(1)) if v else None
                rest += v.end() if v else 0
            e = re.match(r"\s*\)\s*;?", code[rest:])
            if obj is None or e is None:
                return None
            for el, attrs in obj.items():
                for k, v in attrs.items():
                    steps.append(("check", el, m.group(2), k, str(v)))
            pos = rest + e.end()
            continue
        return None
    if not any(st[0] == "check" for st in steps):
        return None
    return steps


def set_inline_style(el, prop, value):
    """el.style.prop = value: replace the inline declaration ("" removes it)."""
    decls = [(k, v) for k, v, imp in parse_decls(el.attrs.get("style", ""))
             if k != prop]
    if value != "":
        decls.append((prop, value))
    el.attrs["style"] = "; ".join("%s: %s" % kv for kv in decls)


def style_change_pages(path, steps):
    """One page per phase, in the state checkLayout sees: the steps up to
    and including that phase's last check replayed on a fresh parse."""
    phases, last = [], {}
    for i, st in enumerate(steps):
        if st[0] != "check":
            continue
        if st[2] in last and any(s[0] == "style" for s in steps[last[st[2]] + 1:i]):
            raise Skip("style-change phase checked across a style change")
        if st[2] not in last:
            phases.append(st[2])
        last[st[2]] = i
    out = []
    for phase in phases:
        page = Page(path)
        byid = {e.id: e for e in Page.walk(page.dom.doc) if e.id}
        for st in steps[:last[phase] + 1]:
            el = byid.get(st[1])
            if el is None:
                raise Skip("style-change element not found")
            if st[0] == "check":
                el.classes.add(st[2])
                el.attrs["class"] = " ".join(sorted(el.classes))
                el.attrs[st[3]] = st[4]
            else:
                set_inline_style(el, st[2], st[3])
        page.cache = {}
        out.append((phase, page))
    return out


def convert_file(path, rel, commit):
    page = Page(path)
    steps = style_change_steps(page)
    if steps is None:
        return convert_page(page, find_check_calls(page), rel, commit)
    cases, skips = [], []
    for phase, ppage in style_change_pages(path, steps):
        try:
            cases.extend(convert_page(ppage, ["." + phase], rel, commit, phase))
        except Skip as e:
            skips.append(str(e))
    if not cases:
        raise Skip(skips[0] if skips else "no checks")
    return cases


def convert_page(page, sels, rel, commit, phase=None):
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
            "id": "%s/%s%s%s" % (SUITE, rel[:-5], "" if phase is None else "/" + phase,
                                 "" if len(roots) == 1 else "/%d" % i),
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
        rs = tree["style"]
        if rs.get("aspectRatio") is not None and rs.get("width", "auto") == "auto" \
                and isinstance(rs.get("height"), (int, float)):
            # The width comes from height x aspect-ratio, not from stretching
            # to the container: a given available width would be laid out
            # exactly, so leave it unconstrained.
            case["available"] = dict(case["available"], width=None)
        if conv.root_sizing == "fit-content" and conv.sized_by_ancestor \
                and rs.get("width", "auto") == "auto" \
                and rs.get("position") not in ("absolute", "fixed"):
            # Shrink-to-fit in an explicitly sized (often narrow) ancestor:
            # say so, and keep that width as the available width, so a
            # width: 0 container gives min-content as in the browser.
            rs["width"] = "fit-content"
            case["available"] = {"width": case["available"]["width"], "height": None}
        elif conv.root_sizing == "fit-content":
            # Shrink-to-fit root: trellis-case lays a given available width
            # out exactly, so leave it unconstrained (content size).
            case["available"] = {"width": None, "height": None}
        if rs.get("position") in ("absolute", "fixed"):
            cb = conv.root_containing_block(root)
            if rs.get("position") == "fixed" and cb is not None:
                # At the root, fixed is absolute against the viewport, which
                # is what the available size below says.
                rs["position"] = "absolute"
            if cb is not None:
                # trellis-case lays an abspos root out against the available
                # size as its containing block: it fills it less the insets
                # when both are set, and shrinks to fit otherwise.
                case["available"] = cb
        if anchor_path is not None:
            case["anchor"] = anchor_path
        if conv.root_margin_collapses(root, tree, exp):
            conv.requires.add("margin-collapse")
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
    report = []         # (status, file, detail) for IMPORT-REPORT.tsv
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
                report.append(("skipped", rel, str(e)))
                continue
            except RecursionError:
                skips["recursion"] += 1
                report.append(("skipped", rel, "recursion"))
                continue
            files += 1
            report.append(("imported", rel, "%d case(s)" % len(cases)))
            for c in cases:
                p = os.path.join(out_dir, c["id"][len(SUITE) + 1:] + ".json")
                os.makedirs(os.path.dirname(p), exist_ok=True)
                with open(p, "w") as f:
                    json.dump(c, f, indent=1)
                    f.write("\n")
                written += 1
    # Which check-layout files were imported and which skipped (and why), so
    # snapshot_diff.py can tell a case deleted upstream from one the
    # importer now skips. Not .json: trellis-case only reads *.json.
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "IMPORT-REPORT.tsv"), "w") as f:
        f.write("# wpt %s %s %s\n" % (commit, sub, SUITE))
        for status, rel, detail in sorted(report, key=lambda r: r[1]):
            f.write("%s\t%s\t%s\n" % (status, rel, detail.replace("\t", " ").replace("\n", " ")))
    print("wpt: wrote %d cases from %d files (%s)" % (written, files, commit[:12]))
    print("wpt: skipped %d files:" % sum(skips.values()))
    for reason, n in skips.most_common():
        print("  %4d  %s" % (n, reason))


if __name__ == "__main__":
    main()
