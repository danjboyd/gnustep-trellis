# Trellis

Responsive layout for GNUstep and Cocoa applications, built on the CSS box
model: Flexbox now, Grid next. Trellis uses exact CSS property names and
semantics, so anyone who knows CSS (people and coding agents alike) can
write Trellis layouts.

Status: **pre-alpha, private.** Licence: LGPL 2.1 or later (COPYING.LIB).

## Layers

| Layer | What it is | Depends on |
|---|---|---|
| Engine (`libTrellisEngine`) | `TRNode`/`TRStyle`: a box tree, CSS parsing, the Flexbox algorithm | Foundation only |
| Views (`libTrellis`) | `TRBoxView`: lays out real NSViews, measured by intrinsic size | AppKit (GNUstep or Apple) |
| Tools | `trellis-case` (layout tests), `trellis-render` (PNG + JSON frames), `trellis-lint` | |

```objc
TRNode *row = [TRNode nodeWithStyle: @"flex-direction: row; gap: 8px; padding: 12px"
                           children: @[
  [TRNode nodeWithStyle: @"flex: 1"],
  [TRNode nodeWithStyle: @{@"width": @80}],
]];
[row layoutWithAvailableSize: TRSizeMake(400, NAN)];
```

## Seeing it

```sh
scripts/run-headless.sh obj/trellis-render Examples/TrellisDemo/AskDetail.trellis \
    --widths 340,520,800 --theme Adwaita --png /tmp/ask.png --json /tmp/ask.json --lint
obj/trellis-lint Examples/TrellisDemo/AskDetail.trellis --owner Examples/TrellisDemo/AskDetailController.h
```

`run-headless.sh` starts a private Xvfb display and points `GNUSTEP_HOME` at
a throwaway directory. trellis-render refuses to run otherwise, so it never
touches real user defaults.

![TrellisDemo .trellis screens at 340, 520 and 800 px under Adwaita](docs/images/demo-adwaita-3-widths.png)

## Building

GNUstep (clang, libobjc2, ARC, libdispatch; GCC is not supported):

```sh
scripts/install-toolchain-debian.sh   # once: builds the toolchain into ~/opt/trellis-toolchain
. scripts/env.sh
make && make check
```

macOS: `make -f Makefile.macos check`.

## Documents

- [docs/design.md](docs/design.md): architecture, API, tools, risks
- [docs/agents.md](docs/agents.md): writing Trellis UI (for coding agents)
- [docs/test-case-format.md](docs/test-case-format.md): JSON layout test cases
- [docs/known-issues.md](docs/known-issues.md)
