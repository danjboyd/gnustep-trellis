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


if __name__ == "__main__":
    unittest.main(verbosity=1)
