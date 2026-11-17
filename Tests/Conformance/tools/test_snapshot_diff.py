#!/usr/bin/env python3
"""Unit tests for snapshot_diff.py (python3 -I, no build needed)."""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import snapshot_diff as S  # noqa: E402

FILE = "css/css-grid/grid-model/gutters.html"


def case(i, width, expected, commit="old"):
    return {"id": "wpt-grid/%s/%d" % (FILE[:-5], i),
            "source": {"suite": "wpt-grid", "file": FILE, "commit": commit},
            "root": {"style": {"display": "grid", "width": width}},
            "expected": {"children": [{"width": expected}]}}


def tree(cases):
    d = tempfile.mkdtemp()
    for c in cases:
        p = os.path.join(d, c["id"] + ".json")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        json.dump(c, open(p, "w"))
    return S.load(d)


class SnapshotDiff(unittest.TestCase):
    def test_commit_bump_only_is_unchanged(self):
        d = S.diff(tree([case(0, 100, 80)]), tree([case(0, 100, 80, commit="new")]))
        self.assertEqual(d["unchanged"], ["wpt-grid/css/css-grid/grid-model/gutters/0"])
        self.assertFalse(d["revised"] or d["added"] or d["removed"])

    def test_revised_expectation(self):
        # The grid-gutters-and-flex-content-001/6 shape: same input, new numbers.
        d = S.diff(tree([case(0, 100, 80)]), tree([case(0, 100, 81)]))
        self.assertEqual(len(d["revised"]), 1)
        self.assertEqual(S.leaf_changes(d["revised"][0]["old"], d["revised"][0]["new"]),
                         ["root/0.width: 80 -> 81"])

    def test_inserted_container_renumbers_instead_of_changing(self):
        old = tree([case(0, 100, 80), case(1, 200, 90)])
        new = tree([case(0, 50, 10), case(1, 100, 80), case(2, 200, 90)])
        d = S.diff(old, new)
        self.assertEqual(sorted(r["was"][-1] for r in d["renumbered"]), ["0", "1"])
        # The inserted container is the one new case; nothing reads as changed.
        self.assertEqual(d["added"], ["wpt-grid/css/css-grid/grid-model/gutters/0"])
        self.assertEqual(d["input-changed"], [])
        self.assertEqual(d["removed"], [])

    def test_input_changed_at_same_index(self):
        d = S.diff(tree([case(0, 100, 80)]), tree([case(0, 120, 80)]))
        self.assertEqual([r["id"] for r in d["input-changed"]],
                         ["wpt-grid/css/css-grid/grid-model/gutters/0"])
        self.assertEqual(d["input-changed"][0]["changes"], ["root.root.style.width: 100 -> 120"])
        self.assertFalse(d["added"] or d["removed"])

    def test_renamed_file_is_moved(self):
        old = case(0, 100, 80)
        new = json.loads(json.dumps(old))
        new["id"] = new["id"].replace("gutters", "gutters-001")
        new["source"]["file"] = FILE.replace("gutters", "gutters-001")
        d = S.diff(tree([old]), tree([new]))
        self.assertEqual(d["moved"], [{"id": new["id"], "was": old["id"]}])
        self.assertFalse(d["added"] or d["removed"])

    def test_import_report_explains_files(self):
        old_r = {FILE: ("imported", "1 case(s)"), "css/x.html": ("imported", "1 case(s)")}
        new_r = {FILE: ("skipped", "writing-mode")}
        rows = S.explain_files("removed", ["wpt-grid/css/css-grid/grid-model/gutters/0"],
                               {"wpt-grid/css/css-grid/grid-model/gutters/0": case(0, 100, 80)},
                               old_r, new_r)
        self.assertEqual(rows, [(FILE, 1, "now skipped: writing-mode")])
        gone = dict(case(0, 100, 80), id="wpt-grid/css/x/0", source={"file": "css/x.html"})
        rows = S.explain_files("removed", [gone["id"]], {gone["id"]: gone}, old_r, new_r)
        self.assertTrue(rows[0][2].startswith("gone upstream"))
        rows = S.explain_files("added", [gone["id"]], {gone["id"]: gone}, {}, new_r)
        self.assertTrue(rows[0][2].startswith("new upstream"))

    def test_report_file_round_trip(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "IMPORT-REPORT.tsv"), "w") as f:
            f.write("# wpt abc css/css-grid wpt-grid\nimported\t%s\t2 case(s)\nskipped\tcss/y.html\tfloat\n" % FILE)
        self.assertEqual(S.load_report(d), {FILE: ("imported", "2 case(s)"), "css/y.html": ("skipped", "float")})
        self.assertIsNone(S.load_report(tempfile.mkdtemp()))

    def test_removed(self):
        d = S.diff(tree([case(0, 100, 80), case(1, 200, 90)]), tree([case(0, 100, 80)]))
        self.assertEqual(d["removed"], ["wpt-grid/css/css-grid/grid-model/gutters/1"])


if __name__ == "__main__":
    unittest.main()
