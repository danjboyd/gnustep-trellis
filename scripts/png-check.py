#!/usr/bin/env python3
"""Check a snapshot PNG without third-party modules (runs on Linux and macOS).

    python3 -I scripts/png-check.py out.png --size 520x400 --appearance dark [--min-colors 8]

Fails (exit 1) when the PNG isn't the expected pixel size, when its
background (the most common colour) is light for --appearance dark or dark
for light, or when it holds fewer than --min-colors distinct colours (a
blank or missing drawing). Prints one line: ok or FAIL with the numbers.
"""
import argparse
import collections
import struct
import sys
import zlib


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, ihdr = 8, b"", None
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", chunk)
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + n
    w, h, depth, ctype, _, _, interlace = ihdr
    if depth != 8 or interlace or ctype not in (0, 2, 4, 6):
        raise ValueError("unsupported PNG (depth %d, colour type %d, interlace %d)" % (depth, ctype, interlace))
    bpp = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        f, line = raw[i], bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b, c = prev[x], prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(line))
        prev = line

    def px(row, x):
        v = row[x * bpp:(x + 1) * bpp]
        return (v[0], v[0], v[0]) if ctype in (0, 4) else tuple(v[:3])
    return w, h, rows, px


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("png")
    ap.add_argument("--size", help="WxH in pixels")
    ap.add_argument("--appearance", choices=["light", "dark"])
    ap.add_argument("--min-colors", type=int, default=8)
    a = ap.parse_args()
    try:
        w, h, rows, px = read_png(a.png)
    except (OSError, ValueError, zlib.error, TypeError) as e:
        print(f"FAIL {a.png}: {e}")
        return 1
    colours = collections.Counter()
    step = max(1, (w * h) // 40000)          # sample at most ~40k pixels
    for y in range(0, h, max(1, int(step ** 0.5))):
        for x in range(0, w, max(1, int(step ** 0.5))):
            colours[px(rows[y], x)] += 1
    bg, _ = colours.most_common(1)[0]
    lum = sum(bg) / (3 * 255)
    problems = []
    if a.size and f"{w}x{h}" != a.size:
        problems.append(f"size {w}x{h}, expected {a.size}")
    if a.appearance == "dark" and lum >= 0.4:
        problems.append(f"background #{bg[0]:02x}{bg[1]:02x}{bg[2]:02x} is light")
    if a.appearance == "light" and lum <= 0.6:
        problems.append(f"background #{bg[0]:02x}{bg[1]:02x}{bg[2]:02x} is dark")
    if len(colours) < a.min_colors:
        problems.append(f"only {len(colours)} colour(s): blank drawing?")
    msg = f"{a.png}: {w}x{h}, background #{bg[0]:02x}{bg[1]:02x}{bg[2]:02x}, {len(colours)} colours"
    print(("FAIL " + msg + "; " + "; ".join(problems)) if problems else ("ok   " + msg))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
