---
name: trellis-mockup
description: Mock up a GNUstep or Cocoa screen with Trellis and render it headless with TrellisPreview and trellis-render, using only obviously fake data. Use when an agent needs to show a proposed native screen (a layout change, a new panel, a review mockup) as PNGs and frame JSON, without building the app. DRAFT.
---

# Trellis mockups

A mockup is a `.trellis` file (markup plus CSS) and a `.sample.json` with
the text to show. Trellis lays it out with the same engine the app uses,
and the tools render it headless to PNGs and frame JSON. You get a
picture of the real native layout at several widths, in light and dark,
without writing or building any Objective-C.

The full markup and CSS guide is `docs/agents.md` in the Trellis repo.
Read sections 1 to 4 before your first mockup. This skill is the short
version, plus the rules for showing a mockup to people.

## Rules

- **Obviously fake data only.** Never put a real person, agent, ticket,
  hostname, customer, path or message in a mockup or its sample file. Use
  "Example Agent A", "DEMO-101", "example-host", "Sample item". A mockup
  is often shared further than you expect.
- **Every GUI run goes through `scripts/run-headless.sh`** (render.sh does
  this for you). It gives each run a private display and a throwaway
  GNUstep home. Never run TrellisPreview or trellis-render against a real
  display or the user's own defaults.
- **Look at the PNGs yourself.** Lint finds clipped text, overlaps and
  overflow, but not a card that sits centred when it should stretch.
- **When you show a mockup to Dan,** send the PNGs, not just a
  description. Through AIManager, attach them with `laptop.open` (images
  only) and name the files in your ask. To let him open it live in
  TrellisPreview as well, add the commands from `handoff.py` to the ask
  (see "Letting Dan open it in TrellisPreview"). Never send a `.trellis`
  or `.json` file through `laptop.open`.

## Setup (once per checkout)

```sh
git clone https://github.com/danjboyd/gnustep-trellis.git trellis && cd trellis
. scripts/env.sh          # first, before you set variables of your own
make -j4                  # top level: builds the tools and ./TrellisPreview.app
make check                # engine and conformance suites; should all pass
```

- `scripts/env.sh` finds the GNUstep toolchain in `TRELLIS_TOOLCHAIN`,
  by default `~/opt/trellis-toolchain` in your account's real home. If
  yours is elsewhere, export `TRELLIS_TOOLCHAIN` before sourcing it.
- There is no separate TrellisPreview build: check that
  `./TrellisPreview.app/TrellisPreview` exists after `make`.
- For isolation, run with your own private `HOME` and a short
  `TRELLIS_GNUSTEP_HOME` (59 bytes or less, e.g. under `/tmp`). Point
  any GNUstep configuration inside that tree, never at your real
  `~/GNUstep`. Changing `HOME` doesn't move the toolchain.
- The renders use the Adwaita theme (`--theme` to change). A new private
  GNUstep home starts with no themes, so copy an Adwaita.theme you
  already have into it before rendering:

  ```sh
  mkdir -p "$TRELLIS_GNUSTEP_HOME/GNUstep/Library/Themes"
  cp -a /path/to/Adwaita.theme "$TRELLIS_GNUSTEP_HOME/GNUstep/Library/Themes/"
  ```

  render.sh stops with a clear message, listing where it looked, if the
  theme is missing. Installing the theme into the toolchain instead is
  optional and a separate change to that toolchain; don't do it as part
  of a mockup.

## The loop

1. **Write `Screen.trellis`** (start from
   `skills/trellis-mockup/example/QueueMockup.trellis`):
   - The root is a `<column>`, `<row>` or `<box>`, and one `<style>`
     block holds the CSS.
   - Elements: `column`, `row`, `box` (`display: grid` makes it a grid),
     `scroll`, `split`, `label` (add `wraps="yes"` for text that should
     wrap), `text` (a wrapping label), `field`, `button`, `checkbox`,
     `radio`, `popup`, `segmented`, `slider`, `progress`, `image`,
     `separator`, `spacer`. See docs/agents.md section 2.
   - Ids become outlets: add `no-outlet="yes"` to labels that are only
     decoration. There's no owner class for a mockup, so lint won't check
     outlets unless you write one.
   - Put `container-type: inline-size` on the root, and use
     `@container (max-width: 520px) { ... }` for narrow layouts.
   - Colours: use system colours (`GrayText`, `CanvasText`) or set a
     background too, so dark mode stays readable. Lint warns otherwise.
   - The table below covers the things that most often go wrong.

   | You want | Write | Not |
   |---|---|---|
   | A segmented control or popup | `items="Now, Today, All"` (commas) | `items="Now\|Today\|All"`, which is one item |
   | A radio, checkbox or button title | `<radio>Daily</radio>` (or `title="Daily"`) | an empty element |
   | A badge or pill (background, border, radius) | `<row class="badge"><label>Urgent</label></row>`, styled on the row | styles on the `<label>`: only boxes draw backgrounds and borders |
   | A search field in a row | `flex: 1` or a `width`/`min-width` on the field | nothing: a field has no useful natural width and shrinks to a sliver |
   | Text that wraps | `<text>` or `<label wraps="yes">` | a plain `<label>`, which clips |
   | Cards that fill the width when stacked | `align-items: stretch` on the stacking row | the row default, which centres |

2. **Write `Screen.sample.json`** next to it: `{"id": "text"}` for each id
   whose text you want to show. Make one string long, to show wrapping.
3. **Render and lint:**

   ```sh
   . scripts/env.sh                      # in the Trellis checkout
   skills/trellis-mockup/render.sh path/to/Screen.trellis "$(mktemp -d)"
   ```

   This runs trellis-lint, then trellis-render at 340, 520 and 900 wide,
   in light and dark. It takes a TrellisPreview snapshot at the widest
   size in both appearances, checks every PNG, and lists what it wrote.
   It exits 0 only when lint, every render and the TrellisPreview check
   are clean, and every expected file was written.
   - The output directory must be new or empty, so nothing from an
     earlier run can pass the checks. Use a fresh one for each run.
   - TrellisPreview is required. If it isn't built, render.sh fails;
     `--no-preview` skips the app check, and then you must say the
     mockup wasn't checked in the app.
   - Linux/GNUstep only for now. On macOS, run `build/trellis-render`
     directly.
   - Flags: `--widths 340,520,900`, `--height 640`,
     `--theme Adwaita|Gumdrop`, `--no-preview`.
   - To use an installed stable Trellis instead of a checkout, set
     `TRELLIS_PREFIX` to a prefix made by `scripts/trellis-update.sh`.
4. **Fix and repeat.** Read lint's findings: `clipped-text` means give
   the text room or let it wrap, `overlap` means siblings collide.
   `Screen-<appearance>-<width>.json` lists every view's frame if you
   need numbers. Then look at the PNGs again.
5. **Show it.** Use the light and dark PNGs at the widths that matter,
   plus the TrellisPreview snapshot. Say what is fake.

The TrellisPreview snapshot is the "what the app shows" check: it loads
the screen the way an app does (the same loader and views). It should
match the trellis-render PNG at the same width and appearance pixel for
pixel. If they differ, report it to the Trellis maintainers, because
that's a bug. If TrellisPreview can't load the file, render.sh fails and
keeps its error snapshot aside as `*.load-error.png`.

## Letting Dan open it in TrellisPreview

Dan has TrellisPreview installed in `~/opt/trellis-stable` on his laptop
and chose to receive mockups as commands he runs himself. After the PNGs:

1. Run `python3 -I skills/trellis-mockup/handoff.py Screen.trellis --json
   commands.json`. It reads `Screen.trellis` and `Screen.sample.json` and
   writes the commands: one line each, every file line single-quoted, and
   a last command that opens the mockup. It checks that they recreate both
   files before it prints them. Don't write or edit these commands by hand.
2. Put the commands, in order, in the ask's `command` field (no host:
   they run on his laptop). In the body, say what they do: they write the
   mockup into `~/agent-shared/trellis-mockups/Screen/` and open it in
   TrellisPreview, and he runs them in one terminal, in order.
3. Exit 3 means the mockup can't go this way: a single quote (use fake
   text without apostrophes), a tab, no final newline, or more than 8
   commands (about 12 KB). Fix the first three, or send the PNGs only.

The same fake-data rule applies: the commands carry the whole mockup.
A newer set of commands for the same screen replaces the files, and an
open TrellisPreview reloads them.

## What a mockup can't show

- Real data volumes. Use the sample file to make one list long if that
  matters.
- Behaviour. Actions and outlets are names only. The mockup shows layout,
  not what a button does.
- Platform differences. The renders are GNUstep with the Adwaita theme.
  Cocoa uses the same layout engine, but its fonts and control sizes
  differ, so expect a few pixels of difference, not a different layout.
