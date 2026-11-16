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


class Validation(unittest.TestCase):
    def test_left_right_not_valid_for_align(self):
        self.assertNotIn("right", W.VALID_KEYWORDS["align-content"])
        self.assertIn("right", W.VALID_KEYWORDS["justify-content"])


if __name__ == "__main__":
    unittest.main(verbosity=1)
