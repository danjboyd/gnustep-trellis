#!/usr/bin/env python3
"""Unit tests for the WPT importer's CSS helpers. Each test pins a bug that
was fixed once; keep them green when changing import_wpt.py.

    python3 -I Tests/Conformance/tools/test_import_wpt.py
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import import_wpt as W  # noqa: E402


class FlexShorthand(unittest.TestCase):
    def test_keywords(self):
        self.assertEqual(W.expand_flex("none"),
                         {"flex-grow": "0", "flex-shrink": "0", "flex-basis": "auto"})
        self.assertEqual(W.expand_flex("auto")["flex-basis"], "auto")

    def test_numbers_and_basis(self):
        self.assertEqual(W.expand_flex("1"),
                         {"flex-grow": "1", "flex-shrink": "1", "flex-basis": "0%"})
        self.assertEqual(W.expand_flex("1 2 3px"),
                         {"flex-grow": "1", "flex-shrink": "2", "flex-basis": "3px"})
        self.assertEqual(W.expand_flex("10px")["flex-grow"], "1")
        self.assertEqual(W.expand_flex("auto 1 1")["flex-basis"], "auto")

    def test_unitless_zero_basis(self):
        # A unitless zero after two flex factors is the basis (flex-flow-013).
        self.assertEqual(W.expand_flex("1 0 0"),
                         {"flex-grow": "1", "flex-shrink": "0", "flex-basis": "0px"})
        self.assertEqual(W.expand_flex("2 1 0"),
                         {"flex-grow": "2", "flex-shrink": "1", "flex-basis": "0px"})
        # Otherwise a zero is still a factor, and three numbers are invalid.
        self.assertEqual(W.expand_flex("0 1")["flex-basis"], "0%")
        self.assertIsNone(W.expand_flex("1 0 1"))

    def test_invalid_is_dropped(self):
        # grow and shrink must be adjacent (flex-shorthand-flex-basis-middle)
        self.assertIsNone(W.expand_flex("1 0% 1"))
        self.assertIsNone(W.expand_flex("-1"))


class Tokens(unittest.TestCase):
    def test_calc_kept_whole(self):
        # gap: calc(10% + 25px) once became row 'calc(10%' and column '+'
        self.assertEqual(W.split_tokens("calc(10% + 25px)"), ["calc(10% + 25px)"])
        self.assertEqual(W.box4("calc(1px + 2px) 5px")["left"], "5px")

    def test_plus_sign_length(self):
        self.assertEqual(W.to_px("+5px", 16), 5)


class MathFunctions(unittest.TestCase):
    def test_calc_tagged_minmax_not(self):
        r = set()
        W.norm_value("calc(10% + 25px)", 16, r)
        self.assertEqual(r, {"css-calc"})
        r = set()
        W.norm_value("repeat(2, minmax(10px, 1fr))", 16, r)
        self.assertEqual(r, set())
        W.norm_value("max(10px, 5%)", 16, r)
        self.assertEqual(r, {"css-calc"})


class GridShorthand(unittest.TestCase):
    def test_rows_cols(self):
        out = W.expand_grid_shorthand("grid", "100px 200px / 50px 1fr")
        self.assertEqual(out["grid-template-rows"], "100px 200px")
        self.assertEqual(out["grid-template-columns"], "50px 1fr")

    def test_auto_flow(self):
        out = W.expand_grid_shorthand("grid", "auto-flow dense 40px / 1fr 1fr")
        self.assertEqual(out["grid-auto-flow"], "row dense")
        self.assertEqual(out["grid-auto-rows"], "40px")

    def test_area_strings_pass_through(self):
        self.assertEqual(W.expand_grid_shorthand("grid-template", '"a b" 10px / 1fr 1fr'),
                         {"grid-template": '"a b" 10px / 1fr 1fr'})


class InlineText(unittest.TestCase):
    def test_br_is_newline(self):
        br = W.El("br", {}, None)
        self.assertEqual(W.inline_text(["X", br, "X"]), "X\nX")

    def test_source_newlines_are_spaces(self):
        br = W.El("br", {}, None)
        self.assertEqual(W.inline_text(["\n  XX  ", br, "\n X X\n"]), "XX\nX X")


class Cascade(unittest.TestCase):
    def test_linked_stylesheet_and_specificity(self):
        d = tempfile.mkdtemp()
        os.makedirs(os.path.join(d, "support"))
        with open(os.path.join(d, "support", "s.css"), "w") as f:
            f.write(".box { display: flex; width: 10px }")
        with open(os.path.join(d, "t.html"), "w") as f:
            f.write('<!DOCTYPE html><link rel="stylesheet" href="support/s.css">'
                    '<style>#b { width: 20px } div.box { height: 5px }</style>'
                    '<body><div id="b" class="box" style="height: 7px"></div></body>')
        p = W.Page(os.path.join(d, "t.html"))
        el = p.dom.body.element_children()[0]
        decl = p.declared(el)
        self.assertEqual(decl["display"], "flex")      # from the linked sheet
        self.assertEqual(decl["width"], "20px")        # id beats class
        self.assertEqual(decl["height"], "7px")        # inline beats rules

    def test_border_width_needs_style(self):
        out = W.expand([("border-width", "5px")])
        self.assertNotIn("border-left-width", out)
        out = W.expand([("border", "5px solid black")])
        self.assertEqual(out["border-left-width"], "5px")


class GridAreas(unittest.TestCase):
    def test_area_names_come_from_own_container(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "t.html"), "w") as f:
            f.write('<!DOCTYPE html><style>.g1{display:grid;grid-template-areas:". a"}'
                    '.g2{display:grid;grid-template-areas:"a-start a-end"}</style><body>'
                    '<div class="g1"><div style="grid-column: a"></div></div>'
                    '<div class="g2"><div style="grid-column: a"></div>'
                    '<div style="grid-column: a-start"></div></div></body>')
        p = W.Page(os.path.join(d, "t.html"))
        g1, g2 = p.dom.body.element_children()
        def tags(item):
            c = W.Converter(p)
            c.style_for(item, "grid")
            return c.requires
        self.assertNotIn("grid-named-lines", tags(g1.element_children()[0]))
        self.assertIn("grid-named-lines", tags(g2.element_children()[0]))
        self.assertNotIn("grid-named-lines", tags(g2.element_children()[1]))


class AbsposContainingBlock(unittest.TestCase):
    PAGE = ('<!DOCTYPE html><script src="/resources/check-layout-th.js"></script>'
            '<style>.c{position:relative;width:200px;height:100px}'
            '.g{display:grid;margin-top:20px}.a{position:absolute;width:10px;height:10px}'
            '</style><body onload="checkLayout(\'.c, .r\')">%s</body>')

    def cases(self, body):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "t.html"), "w") as f:
            f.write(self.PAGE % body)
        return W.convert_file(os.path.join(d, "t.html"), "t.html", "0" * 40)

    def test_static_ancestors_written(self):
        (c,) = self.cases('<div class="c" data-expected-width="200">'
                          '<div><div><div class="a" data-expected-width="10"></div></div></div></div>')
        mid = c["root"]["children"][0]
        self.assertEqual(mid["style"]["position"], "static")
        self.assertEqual(mid["children"][0]["style"]["position"], "static")
        self.assertNotIn("abspos-ancestor-cb", c.get("requires", []))

    def test_grid_beyond_parent_tagged(self):
        (c,) = self.cases('<div class="c g" data-expected-width="200">'
                          '<div><div class="a" data-expected-width="10"></div></div></div>')
        self.assertIn("abspos-grid-descendant", c["requires"])

    def test_margin_through_root_only_when_checked(self):
        body = ('<div class="r" style="width:300px"%s><div class="g">'
                '<div class="a" data-offset-y="0" data-expected-width="10"></div></div></div>')
        (plain,) = self.cases(body % ' data-expected-width="300"')
        self.assertNotIn("margin-collapse", plain.get("requires", []))
        body = ('<div class="c" data-expected-width="200"><div class="g">'
                '<div class="a" data-offset-y="0" data-expected-width="10"></div></div></div>')
        (c,) = self.cases(body)
        self.assertIn("margin-collapse", c["requires"])


class RootContainingBlock(unittest.TestCase):
    def cases(self, style, body, sel):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "t.html"), "w") as f:
            f.write('<!DOCTYPE html><script src="/resources/check-layout-th.js"></script>'
                    '<style>%s</style><body onload="checkLayout(\'%s\')">%s</body>' % (style, sel, body))
        return W.convert_file(os.path.join(d, "t.html"), "t.html", "0" * 40)

    def test_abspos_root_gets_its_containing_block(self):
        st = (".cb{position:relative;width:100px;height:80px;padding:5px}"
              ".t{position:absolute;margin:5px}")
        (inset,) = self.cases(st, '<div class="cb"><div class="t" style="inset:0;width:stretch"'
                              ' data-expected-width="100"></div></div>', ".t")
        self.assertEqual(inset["available"], {"width": 110, "height": 90})
        # No insets: still the containing block (trellis-case shrinks the
        # root to fit within it).
        (plain,) = self.cases(st, '<div class="cb"><div class="t" data-expected-width="0">'
                              '</div></div>', ".t")
        self.assertEqual(plain["available"], {"width": 110, "height": 90})
        # No positioned ancestor: the initial containing block.
        (icb,) = self.cases(st, '<div><div class="t" style="left:0;right:0"'
                            ' data-expected-width="790"></div></div>', ".t")
        self.assertEqual(icb["available"]["width"], 800)
        # A fixed root is absolute against the viewport.
        (fx,) = self.cases(st, '<div class="t" style="position:fixed;width:10px"'
                           ' data-expected-width="10"></div>', ".t")
        self.assertEqual(fx["root"]["style"]["position"], "absolute")
        self.assertEqual(fx["available"], {"width": 800, "height": 600})

    def test_stretch_root_gets_parent_height(self):
        (c,) = self.cases("", '<div style="height:100px;border-top:solid;border-bottom:solid"><div class="r" style="height:stretch"'
                          ' data-expected-height="100"></div></div>', ".r")
        self.assertEqual(c["available"]["height"], 100)
        self.assertNotIn("margin-collapse", c.get("requires", []))

    def test_stretch_margins_zeroed_in_non_bfc(self):
        # CSSWG #11044: in a parent that isn't a BFC, a stretch box's margin
        # on a side without border/padding counts as 0.
        body = ('<div class="o"%s><div class="i" style="height:stretch;margin:10px"'
                ' data-expected-height="100"></div></div>')
        (c,) = self.cases(".o{width:100px;height:100px;position:relative}", body % "", ".i")
        self.assertIn("margin-collapse", c["requires"])
        (bfc,) = self.cases(".o{width:100px;height:100px;position:relative}",
                            body % ' style="overflow:hidden;padding:1px 0"', ".i")
        self.assertNotIn("margin-collapse", bfc.get("requires", []))
        # The root itself stretched in a plain parent.
        (r,) = self.cases("", '<div style="height:200px"><div class="r" style="height:stretch;'
                          'margin:10px" data-expected-height="200"></div></div>', ".r")
        self.assertIn("margin-collapse", r["requires"])

    def test_stretch_min_height_needs_cb_height(self):
        (c,) = self.cases("", '<div style="height:100px"><div class="r" style="min-height:stretch"'
                          ' data-expected-height="100"></div></div>', ".r")
        self.assertIn("containing-block-height", c["requires"])
        (auto,) = self.cases("", '<div><div class="r" style="min-height:stretch"'
                             ' data-expected-height="0"></div></div>', ".r")
        self.assertNotIn("containing-block-height", auto.get("requires", []))


class FitContentRoot(unittest.TestCase):
    def test_float_in_zero_width_div_is_fit_content_in_zero(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "t.html"), "w") as f:
            f.write('<!DOCTYPE html><script src="/resources/check-layout-th.js"></script>'
                    '<body onload="checkLayout(\'.f\')"><div style="width:0">'
                    '<div class="f" style="float:left;display:flex" data-expected-width="10">'
                    '<div style="width:10px"></div></div></div></body>')
        (c,) = W.convert_file(os.path.join(d, "t.html"), "t.html", "0" * 40)
        self.assertEqual(c["root"]["style"]["width"], "fit-content")
        self.assertEqual(c["available"]["width"], 0)
        self.assertNotIn("intrinsic-size-keyword", c.get("requires", []))


class AttributeSelectors(unittest.TestCase):
    def test_presence_and_value(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "t.html"), "w") as f:
            f.write('<!DOCTYPE html><style>[data-expected-height] { width: 7px }'
                    ' div[data-k="v"] { height: 3px }</style><body>'
                    '<div data-expected-height="1" data-k="v"></div><div data-k="w"></div></body>')
        p = W.Page(os.path.join(d, "t.html"))
        a, b = p.dom.body.element_children()
        self.assertEqual(p.declared(a).get("width"), "7px")
        self.assertEqual(p.declared(a).get("height"), "3px")
        self.assertNotIn("height", p.declared(b))


class AspectRatio(unittest.TestCase):
    def ratio(self, v):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "t.html"), "w") as f:
            f.write('<!DOCTYPE html><body><div style="aspect-ratio: %s"></div></body>' % v)
        p = W.Page(os.path.join(d, "t.html"))
        c = W.Converter(p)
        return c.style_for(p.dom.body.element_children()[0], "block")["aspectRatio"]

    def test_forms(self):
        self.assertEqual(self.ratio("2 / 1"), 2)
        self.assertEqual(self.ratio("1.5"), 1.5)
        self.assertEqual(self.ratio("auto 2/1"), "auto 2")
        self.assertEqual(self.ratio("auto"), "auto")


class AvailableHeight(unittest.TestCase):
    def avail(self, body_style):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "t.html"), "w") as f:
            f.write('<!DOCTYPE html><body%s><div style="display: flex; height: 10%%">'
                    '</div></body>' % body_style)
        p = W.Page(os.path.join(d, "t.html"))
        return W.Converter(p).available_height_for_root(p.dom.body.element_children()[0])

    def test_percent_of_a_definite_body(self):
        # percentage-heights-001: <body style="height: 800px">, root height 10%
        self.assertEqual(self.avail(' style="height: 800px"'), 800)

    def test_percent_of_an_auto_body_does_not_resolve(self):
        self.assertIsNone(self.avail(""))


class AhemImportAndMarginCollapse(unittest.TestCase):
    def test_ahem_import_is_ignored_other_imports_skip(self):
        self.assertEqual(W.parse_stylesheet('@import "/fonts/ahem.css"; .a { width: 1px }'),
                         [(".a", [("width", "1px", False)])])
        with self.assertRaises(W.Skip):
            W.parse_stylesheet('@import "other.css"; .a { width: 1px }')

    def test_margin_collapse(self):
        kid = lambda **m: {"style": {"margin" + k: v for k, v in m.items()}}
        # Same-sign adjacent sibling margins collapse; opposite signs sum anyway.
        self.assertTrue(W.margins_collapse({}, [kid(Bottom=5), kid(Top=5)], True))
        self.assertFalse(W.margins_collapse({}, [kid(Bottom=5), kid(Top=-5)], True))
        self.assertFalse(W.margins_collapse({}, [kid(Bottom=5), kid(Top=0)], True))
        # A first child's margin collapses through a parent without padding,
        # unless the parent is a formatting-context root.
        self.assertTrue(W.margins_collapse({}, [kid(Top=5)], False))
        self.assertFalse(W.margins_collapse({"paddingTop": 1}, [kid(Top=5)], False))
        self.assertFalse(W.margins_collapse({}, [kid(Top=5)], True))


class InlineGrid(unittest.TestCase):
    def requires(self, html):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "t.html"), "w") as f:
            f.write('<!DOCTYPE html><body>%s</body>' % html)
        p = W.Page(os.path.join(d, "t.html"))
        root = p.dom.body.element_children()[0]
        c = W.Converter(p)
        c.build(root, "block", [])
        return c.requires

    def test_root_inline_grid_is_a_grid(self):
        self.assertNotIn("display-inline-grid",
                         self.requires('<div style="display: inline-grid"><div></div></div>'))

    def test_inline_grid_on_a_line_needs_inline_formatting(self):
        self.assertIn("display-inline-grid",
                      self.requires('<div><div style="display: inline-grid"></div></div>'))

    def test_inline_grid_item_is_blockified(self):
        self.assertNotIn("display-inline-grid",
                         self.requires('<div style="display: flex"><div style="display: inline-grid"></div></div>'))


class Validation(unittest.TestCase):
    def test_left_right_not_valid_for_align(self):
        self.assertNotIn("right", W.VALID_KEYWORDS["align-content"])
        self.assertIn("right", W.VALID_KEYWORDS["justify-content"])



class FixedUnits(unittest.TestCase):
    def page(self, src):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "t.html"), "w") as f:
            f.write(src)
        return W.Page(os.path.join(d, "t.html"))

    def test_absolute_units(self):
        self.assertEqual(W.norm_value("1in", 16, set()), 96)
        self.assertEqual(W.norm_value("12pt", 16, set()), 16)
        self.assertEqual(W.norm_value("2pc", 16, set()), 32)
        self.assertEqual(W.norm_value("2.54cm", 16, set()), 96)
        self.assertEqual(W.norm_value("40Q", 16, set()), 37.7953)

    def test_rem_uses_the_root_font_size(self):
        self.page('<!DOCTYPE html><body></body>')
        self.assertEqual(W.norm_value("minmax(2rem, auto) auto", 10, set()),
                         "minmax(32px, auto) auto")
        self.page('<!DOCTYPE html><html style="font-size: 10px"><body></body></html>')
        self.assertEqual(W.to_px("2rem", 99), 20)
        # A rem in the root's own font-size is relative to the initial 16px.
        self.page('<!DOCTYPE html><html style="font-size: 2rem"><body></body></html>')
        self.assertEqual(W.to_px("1rem", 99), 32)

    def test_identifiers_are_left_alone(self):
        self.assertEqual(W.fixed_units_to_px('"a1in b" item2pt'), '"a1in b" item2pt')

    def test_font_relative_units_still_skip(self):
        for v in ("2ch", "1ex", "3vw", "1lh"):
            with self.assertRaises(W.Skip):
                W.norm_value(v, 16, set())


class NthChild(unittest.TestCase):
    def test_an_b(self):
        self.assertEqual(W.parse_an_b("odd"), (2, 1))
        self.assertEqual(W.parse_an_b("2n + 1"), (2, 1))
        self.assertEqual(W.parse_an_b("-n+3"), (-1, 3))
        self.assertEqual(W.parse_an_b("n"), (1, 0))
        self.assertEqual(W.parse_an_b("4"), (0, 4))
        self.assertIsNone(W.parse_an_b("2n of .x"))

    def test_matching(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "t.html"), "w") as f:
            f.write('<!DOCTYPE html><style>div:nth-child(2n) { width: 1px }'
                    ' span:nth-last-child(-n + 2) { height: 2px }'
                    ' span:nth-of-type(3n+1) { order: 3 }</style><body>'
                    + "<div></div>" * 5 + "<span></span>" * 4 + '</body>')
        p = W.Page(os.path.join(d, "t.html"))
        kids = p.dom.body.element_children()
        self.assertEqual([("width" in p.declared(k)) for k in kids[:5]],
                         [False, True, False, True, False])
        self.assertEqual([("height" in p.declared(k)) for k in kids[5:]],
                         [False, False, True, True])
        self.assertEqual([("order" in p.declared(k)) for k in kids[5:]],
                         [True, False, False, True])

    def test_of_selector_skips(self):
        with self.assertRaises(W.Skip):
            W.parse_selector("div:nth-child(2n of .x)")


class StyleChange(unittest.TestCase):
    """css-grid/alignment's support/style-change.js tests: each phase
    (before/after an inline style change) imports as its own case."""
    HEAD = ('<!DOCTYPE html><script src="/resources/check-layout-th.js"></script>'
            '<script src="support/style-change.js"></script>'
            '<style>#grid{display:grid;grid-template-columns:100px;grid-template-rows:200px;'
            'align-items:stretch}.after{margin-left:5px}</style>')

    def cases(self, script, body, onload="document.fonts.ready.then(() => { runTest(); })"):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "t.html"), "w") as f:
            f.write(self.HEAD + "<script>" + script + "</script>"
                    + '<body onload="%s">%s</body>' % (onload, body))
        return W.convert_file(os.path.join(d, "t.html"), "t.html", "0" * 40)

    BODY = '<div id="grid"><div id="item" data-expected-width="100"></div></div>'

    def test_single_property_change(self):
        cs = self.cases('setup({ explicit_done: true });\nfunction runTest() {\n'
                        '  evaluateStyleChange(item, "before", "data-expected-height", 200);\n'
                        '  grid.style.alignItems = "start";\n'
                        '  evaluateStyleChange(item, "after", "data-expected-height", 0);\n'
                        '  done();\n}', self.BODY)
        self.assertEqual([c["id"].rsplit("/", 1)[1] for c in cs], ["before", "after"])
        before, after = cs
        self.assertEqual(before["root"]["style"]["alignItems"], "stretch")
        self.assertEqual(after["root"]["style"]["alignItems"], "start")
        self.assertEqual(before["expected"]["children"][0]["height"], 200)
        self.assertEqual(after["expected"]["children"][0]["height"], 0)
        # The phase class is on the element from its phase on: .after rules
        # apply only to the after case.
        self.assertNotIn("marginLeft", before["root"]["children"][0]["style"])
        self.assertEqual(after["root"]["children"][0]["style"].get("marginLeft"), 5)

    def test_multiple_with_variables_and_reset(self):
        body = ('<div id="grid"><div id="item" style="align-self: start" data-expected-width="100">'
                '</div></div>')
        cs = self.cases("function runTest() {\n"
                        "    let before = {\n        item: {'data-expected-height': 0},\n    };\n"
                        "    let after = { item: {\"data-expected-height\": 200 } };\n"
                        "    evaluateStyleChangeMultiple('before', before);\n"
                        "    item.style.alignSelf = '';\n"
                        "    evaluateStyleChangeMultiple('after', after);\n"
                        "    done();\n}", body, onload="runTest()")
        before, after = cs
        self.assertEqual(before["root"]["children"][0]["style"].get("alignSelf"), "start")
        self.assertNotEqual(after["root"]["children"][0]["style"].get("alignSelf"), "start")
        self.assertEqual(after["expected"]["children"][0]["height"], 200)

    def test_other_script_still_skips(self):
        with self.assertRaises(W.Skip):
            self.cases('function runTest() {\n'
                       '  evaluateStyleChange(item, "before", "data-expected-height", 200);\n'
                       '  item.offsetWidth;\n'
                       '  grid.style.alignItems = "start";\n'
                       '  evaluateStyleChange(item, "after", "data-expected-height", 0);\n'
                       '  done();\n}', self.BODY)

    def test_phase_split_by_a_change_skips(self):
        with self.assertRaises(W.Skip):
            self.cases('function runTest() {\n'
                       '  evaluateStyleChange(item, "before", "data-expected-height", 200);\n'
                       '  grid.style.alignItems = "start";\n'
                       '  evaluateStyleChange(item, "before", "data-expected-width", 100);\n'
                       '  done();\n}', self.BODY)


if __name__ == "__main__":
    unittest.main(verbosity=1)
