#!/usr/bin/env python3
"""Unit tests for scripts/png-check.py with synthetic PNGs (python3 -I)."""
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
CHECK = os.path.join(HERE, "..", "..", "scripts", "png-check.py")


def png(path, w, h, pixel, filt=0):
    """RGB PNG; pixel(x, y) -> (r, g, b). filt 1 (Sub) exercises unfiltering."""
    raw = b""
    for y in range(h):
        row = bytes(c for x in range(w) for c in pixel(x, y))
        if filt == 1:
            row = bytes((row[i] - (row[i - 3] if i >= 3 else 0)) & 255 for i in range(len(row)))
        raw += bytes([filt]) + row

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def run(*args):
    return subprocess.run([sys.executable, "-I", CHECK, *args], capture_output=True, text=True).returncode


def ui(bg):
    # A background with a few drawn shades, like a screen.
    return lambda x, y: bg if (x // 10 + y // 10) % 4 else ((x * 7) % 256, (y * 5) % 256, 128)


class PngCheck(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def p(self, name):
        return os.path.join(self.d, name)

    def test_dark_screen_passes_as_dark_only(self):
        png(self.p("d.png"), 52, 40, ui((50, 50, 50)))
        self.assertEqual(run(self.p("d.png"), "--size", "52x40", "--appearance", "dark"), 0)
        self.assertEqual(run(self.p("d.png"), "--appearance", "light"), 1)

    def test_light_screen_with_sub_filter(self):
        png(self.p("l.png"), 52, 40, ui((236, 236, 236)), filt=1)
        self.assertEqual(run(self.p("l.png"), "--appearance", "light"), 0)

    def test_wrong_size_and_blank(self):
        png(self.p("b.png"), 52, 40, lambda x, y: (236, 236, 236))
        self.assertEqual(run(self.p("b.png"), "--size", "104x80"), 1)
        self.assertEqual(run(self.p("b.png")), 1)   # one colour: blank

    def test_not_a_png(self):
        open(self.p("x.png"), "w").write("nope")
        self.assertEqual(run(self.p("x.png")), 1)


if __name__ == "__main__":
    unittest.main()
