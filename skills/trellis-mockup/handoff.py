#!/usr/bin/env python3
"""Turn a mockup into the commands Dan runs to open it in TrellisPreview.

    python3 -I skills/trellis-mockup/handoff.py Screen.trellis [--json out.json]

Reads Screen.trellis and, if present, Screen.sample.json next to it, and
prints the commands for an AIManager ask's command field: one line each,
2000 characters at most, 8 at most. Each writes file lines with
printf '%s\\n' 'line' ... into ~/agent-shared/trellis-mockups/Screen/; the
last one opens the mockup with the TrellisPreview installed in
~/opt/trellis-stable. Every file line is a single-quoted string, so
nothing in the files runs.

Before printing, it runs the commands (all but the open command) with a
throwaway HOME and checks they recreate both files byte for byte.

Exit status: 0 ok; 2 usage or unreadable input; 3 the mockup can't be
sent this way (a single quote, a tab or other control character, no final
newline, or too big for 8 commands): send PNGs only.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

LIMIT = 1990          # the ask tool allows 2000 characters per command
MAX_COMMANDS = 8      # the ask tool allows 8 commands
PREVIEW = "~/opt/trellis-stable/current/Applications/TrellisPreview.app/TrellisPreview"


def fail(code, msg):
    print("handoff: " + msg, file=sys.stderr)
    sys.exit(code)


def lines_of(path):
    with open(path, "rb") as f:
        data = f.read()
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        fail(3, "%s is not UTF-8: send PNGs only" % path)
    if text and not text.endswith("\n"):
        fail(3, "%s doesn't end with a newline: add one and run again" % path)
    lines = text.split("\n")[:-1] if text else []
    for n, line in enumerate(lines, 1):
        if "'" in line:
            fail(3, "%s line %d has a single quote, which can't go in a quoted command line: "
                    "reword it (fake data can avoid apostrophes) or send PNGs only" % (path, n))
        if re.search(r"[\x00-\x1f\x7f]", line):
            fail(3, "%s line %d has a tab or other control character: use spaces, "
                    "or send PNGs only" % (path, n))
    return lines


def commands_for(name, files):
    """files: [(filename, lines)] -> list of one-line commands."""
    d = "D=~/agent-shared/trellis-mockups/%s" % name
    out = []
    first = True
    for filename, lines in files:
        op = ">"
        chunk = []

        def cmd(chunk, op, first):
            return (d + " && " + ('mkdir -p "$D" && ' if first else "")
                    + "printf '%s\\n' " + " ".join("'" + l + "'" for l in chunk)
                    + ' %s "$D/%s"' % (op, filename))

        for line in lines:
            if chunk and len(cmd(chunk + [line], op, first)) > LIMIT:
                out.append(cmd(chunk, op, first))
                chunk, op, first = [], ">>", False
            chunk.append(line)
            if len(cmd(chunk, op, first)) > LIMIT:
                fail(3, "a line of %s is too long for one command: send PNGs only" % filename)
        if lines:
            out.append(cmd(chunk, op, first))
            first = False
    out.append(d + " && . ~/opt/trellis-stable/env.sh && " + PREVIEW + ' "$D/%s.trellis" &' % name)
    return out


def verify(name, commands, sources):
    with tempfile.TemporaryDirectory(prefix="handoff.") as home:
        env = dict(os.environ, HOME=home)
        for c in commands[:-1]:
            subprocess.run(["bash", "-c", c], env=env, check=True)
        for filename, path in sources:
            got = os.path.join(home, "agent-shared", "trellis-mockups", name, filename)
            with open(path, "rb") as a, open(got, "rb") as b:
                if a.read() != b.read():
                    fail(2, "self-check failed: %s doesn't round-trip (a bug in handoff.py)" % filename)


def main(argv):
    if len(argv) not in (2, 4) or not argv[1].endswith(".trellis") or (len(argv) == 4 and argv[2] != "--json"):
        fail(2, "usage: handoff.py Screen.trellis [--json out.json]")
    spec = argv[1]
    name = os.path.basename(spec)[:-len(".trellis")]
    if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
        fail(2, "the file name must be letters, digits, - or _ only (got %r)" % name)
    if not os.path.isfile(spec):
        fail(2, "no such file: " + spec)
    sources = [(name + ".trellis", spec)]
    sample = spec[:-len(".trellis")] + ".sample.json"
    if os.path.isfile(sample):
        sources.append((name + ".sample.json", sample))
    files = [(fn, lines_of(p)) for fn, p in sources]
    commands = commands_for(name, files)
    if len(commands) > MAX_COMMANDS:
        fail(3, "the mockup needs %d commands, more than the %d an ask holds: send PNGs only"
                % (len(commands), MAX_COMMANDS))
    verify(name, commands, sources)
    if len(argv) == 4:
        with open(argv[3], "w") as f:
            json.dump([{"text": c} for c in commands], f, indent=1)
            f.write("\n")
    for c in commands:
        print(c)
    print("handoff: %d command(s), checked: they recreate %s" % (len(commands), " and ".join(fn for fn, _ in sources)),
          file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv)
