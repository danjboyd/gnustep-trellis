#!/usr/bin/env python3
"""Regression checks for Tests/Parity/pe-deps.py, on synthetic PE files.

Writes minimal PE32+ images (headers, one section, import and
delay-import tables; no code) into a temporary directory and checks how
pe-deps.py classes their DLLs: recursion through shipped DLLs, names
matched without case, delay-loaded imports, API sets and --system as
system, the program's folder searched first, and a missing DLL (exit 1).
Needs nothing but Python, so it runs in make check on every platform.
Prints PE-DEPS OK, or the failing checks and exit 1.
"""
import json
import os
import struct
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
PEDEPS = os.path.join(HERE, "..", "Parity", "pe-deps.py")
VA, RAW = 0x1000, 0x400


def pe(path, imports=(), delay=()):
    """A PE32+ image whose import (and delay-import) tables name these DLLs."""
    nimp, ndel = len(imports), len(delay)
    imp_at = 0
    del_at = imp_at + 20 * (nimp + 1)
    thunk_at = del_at + 32 * (ndel + 1)           # one empty (zero) thunk list, shared
    names_at = thunk_at + 8
    names, offs = b"", []
    for n in list(imports) + list(delay):
        offs.append(names_at + len(names))
        names += n.encode() + b"\0"
    body = b""
    for k in range(nimp):
        body += struct.pack("<IIIII", VA + thunk_at, 0, 0, VA + offs[k], VA + thunk_at)
    body += b"\0" * 20
    for k in range(ndel):
        body += struct.pack("<IIIIIIII", 1, VA + offs[nimp + k], 0, 0, 0, 0, 0, 0)
    body += b"\0" * 32 + b"\0" * 8 + names
    body += b"\0" * (-len(body) % 0x200)

    dos = b"MZ" + b"\0" * 0x3A + struct.pack("<I", 0x40)
    coff = struct.pack("<HHIIIHH", 0x8664, 1, 0, 0, 0, 240, 0x22)
    dirs = [(0, 0)] * 16
    if nimp:
        dirs[1] = (VA + imp_at, 20 * (nimp + 1))
    if ndel:
        dirs[13] = (VA + del_at, 32 * (ndel + 1))
    opt = struct.pack("<HBB", 0x20B, 14, 0) + b"\0" * (108 - 4) + struct.pack("<I", 16)
    opt = opt[:108] + struct.pack("<I", 16) + b"".join(struct.pack("<II", *d) for d in dirs)
    sec = b".idata\0\0" + struct.pack("<IIIIIIHHI", len(body), VA, len(body), RAW, 0, 0, 0, 0, 0xC0000040)
    head = dos + b"PE\0\0" + coff + opt + sec
    open(path, "wb").write(head + b"\0" * (RAW - len(head)) + body)


def main():
    bad, done = [], []

    def check(label, cond, out):
        done.append(label)
        if not cond:
            bad.append("%s:\n%s" % (label, out))

    with tempfile.TemporaryDirectory(prefix="pe-deps-") as t:
        app, tc, sysd = (os.path.join(t, d) for d in ("app", "tc", "sys"))
        for d in (app, tc, sysd):
            os.makedirs(d)
        pe(os.path.join(app, "Preview.exe"), ["libTrellis.dll", "KERNEL32.dll", "api-ms-win-crt-runtime-l1-1-0.dll"],
           delay=["Lazy.dll"])
        pe(os.path.join(app, "libTrellis.dll"), ["libgnustep-gui-0.32.DLL", "kernel32.dll"])
        pe(os.path.join(tc, "libgnustep-gui-0.32.dll"), ["libobjc.dll", "USER32.dll"])
        pe(os.path.join(tc, "libobjc.dll"), ["KERNEL32.dll"])
        pe(os.path.join(tc, "lazy.dll"))
        pe(os.path.join(tc, "libTrellis.dll"), ["shadowed.dll"])   # app's own copy must win
        for f in ("kernel32.dll", "user32.dll"):
            open(os.path.join(sysd, f), "wb").close()

        js = os.path.join(t, "deps.json")
        p = subprocess.run([sys.executable, "-I", PEDEPS, "--json", js, "--system", sysd,
                            os.path.join(app, "Preview.exe"), tc], capture_output=True, text=True)
        out = p.stdout + p.stderr
        check("exit 0 when nothing is missing", p.returncode == 0, out)
        rows = {e["name"].lower(): e for e in json.load(open(js))["dlls"]} if os.path.exists(js) else {}
        cls = {k: e["class"] for k, e in rows.items()}
        check("program folder first", rows.get("libtrellis.dll", {}).get("path", "").startswith(app), out)
        check("shadowed copy not followed", "shadowed.dll" not in cls, out)
        check("recursion and case", cls.get("libgnustep-gui-0.32.dll") == "ship" and cls.get("libobjc.dll") == "ship", out)
        check("delay-load import", cls.get("lazy.dll") == "ship", out)
        check("system folder", cls.get("kernel32.dll") == "system" and cls.get("user32.dll") == "system", out)
        check("API set is system", cls.get("api-ms-win-crt-runtime-l1-1-0.dll") == "system", out)
        check("each DLL once", len(rows) == 7 and sorted(rows["kernel32.dll"]["needed_by"]) ==
              ["Preview.exe", "libTrellis.dll", "libobjc.dll"], out)
        check("summary line", "== 7 DLL(s): 4 to ship, 3 system, 0 missing" in out, out)

        p = subprocess.run([sys.executable, "-I", PEDEPS, "--system", sysd, os.path.join(app, "Preview.exe")],
                           capture_output=True, text=True)
        out = p.stdout + p.stderr
        check("missing DLLs fail", p.returncode == 1 and "2 missing: Lazy.dll, libgnustep-gui-0.32.DLL" in out, out)
        not_pe = os.path.join(t, "not.exe")
        open(not_pe, "wb").write(b"#!/bin/sh\n")
        p = subprocess.run([sys.executable, "-I", PEDEPS, not_pe], capture_output=True, text=True)
        check("not a PE file", p.returncode != 0 and "not a PE file" in p.stdout + p.stderr, p.stdout + p.stderr)

    if bad:
        print("PE-DEPS FAIL (%d)" % len(bad))
        for b in bad:
            print("- " + b)
        return 1
    print("PE-DEPS OK (%d checks)" % len(done))
    return 0


if __name__ == "__main__":
    sys.exit(main())
