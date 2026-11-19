#!/usr/bin/env python3
"""The DLLs a Windows program really loads, for the packaging contract.

    pe-deps.py [--json OUT.json] [--system DIR]... PROGRAM.exe [SEARCH_DIR...]

Reads the PE import tables (normal and delay-load) of PROGRAM and of every
DLL it pulls in, recursively, without running anything and without
objdump (pure Python, so it also runs in make check on Linux). Each DLL
name is looked up, ignoring case, in PROGRAM's folder and then in each
SEARCH_DIR in order, as the Windows loader would along PATH.

Every DLL is classed:
  system   in a --system folder (default: %SystemRoot%\\System32 when it
           exists), or an api-ms-win-*/ext-ms-* API set: Windows provides it
  ship     found in PROGRAM's folder or a SEARCH_DIR: the installer must
           carry it
  missing  found nowhere: the program won't start (exit 1)

Prints one line per DLL; --json writes {program, dlls: [{name, class,
path, needed_by}]}. Exit 0 when nothing is missing.
"""
import json
import os
import struct
import sys


def imports(path):
    """DLL names in PATH's import and delay-import tables."""
    data = open(path, "rb").read()
    if data[:2] != b"MZ":
        raise ValueError("%s: not a PE file" % path)
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("%s: no PE signature" % path)
    nsec, = struct.unpack_from("<H", data, pe + 6)
    optsize, = struct.unpack_from("<H", data, pe + 20)
    opt = pe + 24
    magic, = struct.unpack_from("<H", data, opt)
    dirs = opt + (112 if magic == 0x20B else 96)
    ndirs, = struct.unpack_from("<I", data, dirs - 4)
    secs = []
    for i in range(nsec):
        s = opt + optsize + 40 * i
        vsize, va, rawsize, raw = struct.unpack_from("<IIII", data, s + 8)
        secs.append((va, max(vsize, rawsize), raw))

    def off(rva):
        for va, size, raw in secs:
            if va <= rva < va + size:
                return raw + rva - va
        raise ValueError("%s: RVA 0x%x is outside every section" % (path, rva))

    def cstr(rva):
        o = off(rva)
        return data[o:data.index(b"\0", o)].decode("ascii", "replace")

    names = []
    for index, size, name_at in ((1, 20, 12), (13, 32, 4)):     # imports, delay imports
        if index >= ndirs:
            continue
        rva, dsize = struct.unpack_from("<II", data, dirs + 8 * index)
        if not rva or not dsize:
            continue
        o = off(rva)
        while True:
            desc = data[o:o + size]
            if len(desc) < size or desc == b"\0" * size:
                break
            n, = struct.unpack_from("<I", desc, name_at)
            if n:
                names.append(cstr(n))
            o += size
    return names


def is_api_set(name):
    n = name.lower()
    return n.startswith("api-ms-win-") or n.startswith("ext-ms-")


def listing(d):
    try:
        return {f.lower(): os.path.join(d, f) for f in os.listdir(d)}
    except OSError:
        return {}


def main(argv):
    args, out, system = list(argv[1:]), None, []
    while args and args[0].startswith("--"):
        opt = args.pop(0)
        if opt == "--json" and args:
            out = args.pop(0)
        elif opt == "--system" and args:
            system.append(args.pop(0))
        else:
            print(__doc__, file=sys.stderr)
            return 2
    if not args:
        print(__doc__, file=sys.stderr)
        return 2
    program, search = args[0], [os.path.dirname(os.path.abspath(args[0]))] + args[1:]
    if not system and os.environ.get("SystemRoot"):
        system = [os.path.join(os.environ["SystemRoot"], "System32")]
    sysmap, dirmaps = {}, [listing(d) for d in search]
    for d in system:
        sysmap.update(listing(d))

    found, todo = {}, [(program, None)]
    while todo:
        path, _ = todo.pop(0)
        try:
            names = imports(path)
        except (OSError, ValueError, struct.error) as e:
            print("FAIL %s" % e)
            return 1
        for name in names:
            key = name.lower()
            if key in found:
                if os.path.basename(path) not in found[key]["needed_by"]:
                    found[key]["needed_by"].append(os.path.basename(path))
                continue
            entry = {"name": name, "class": "missing", "path": None, "needed_by": [os.path.basename(path)]}
            found[key] = entry
            if is_api_set(name) or key in sysmap:
                entry["class"], entry["path"] = "system", sysmap.get(key)
                continue
            for m in dirmaps:
                if key in m:
                    entry["class"], entry["path"] = "ship", m[key]
                    todo.append((m[key], name))
                    break
    rows = sorted(found.values(), key=lambda e: ({"missing": 0, "ship": 1, "system": 2}[e["class"]], e["name"].lower()))
    for e in rows:
        print("%-7s %-34s %s  (needed by %s)" % (e["class"], e["name"], e["path"] or "-", ", ".join(e["needed_by"])))
    missing = [e["name"] for e in rows if e["class"] == "missing"]
    print("== %d DLL(s): %d to ship, %d system, %d missing%s"
          % (len(rows), sum(e["class"] == "ship" for e in rows), sum(e["class"] == "system" for e in rows),
             len(missing), ": " + ", ".join(missing) if missing else ""))
    if out:
        json.dump({"program": os.path.basename(program), "dlls": rows}, open(out, "w"), indent=1)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
