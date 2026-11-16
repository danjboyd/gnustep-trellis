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

### Trellis Preview

`TrellisPreview.app` opens a `.trellis` file and reloads it whenever the
file (or its `.sample.json`) changes. Resize the window to watch the
layout respond, or use View > Width presets. View > Inspector draws box
outlines and lint findings in place, and the Theme menu switches the
GSTheme (light or dark on macOS).

![Preview inspector: lint findings drawn in place](docs/images/preview-inspector.png)

## Building

GNUstep (clang, libobjc2, ARC, libdispatch; GCC is not supported):

```sh
scripts/install-toolchain-debian.sh   # once: builds the toolchain into ~/opt/trellis-toolchain
. scripts/env.sh
make && make check
```

macOS (plain Apple clang, no Xcode project or GNUstep make needed):

```sh
make -f Makefile.macos check   # engine, trellis-case, engine + conformance cases
make -f Makefile.macos gui     # libTrellis (views), trellis-lint/-render/-bench, TrellisPreview.app
```

On macOS `trellis-render` draws the view tree straight into a bitmap,
with no window or `NSApplication`, so it runs headless over ssh.

## Conformance

`make check` runs Trellis's own engine cases and then the imported
Flexbox conformance suites in [Tests/Conformance](Tests/Conformance)
(format: [docs/test-case-format.md](docs/test-case-format.md); sources
and licences: [ATTRIBUTION.md](Tests/Conformance/ATTRIBUTION.md)):

| Suite | Source | Linux (GNUstep) | macOS (Cocoa) |
|---|---|---|---|
| engine | hand-written, `Tests/Engine/cases` | 93/93 | 93/93 |
| yoga | facebook/yoga gentest, 1086 cases | 906/906 | 906/906 |
| wpt | web-platform-tests css-flexbox (check-layout), 957 cases | 813/824 (98.7%) | 813/824 (98.7%) |
| **all conformance** | | **1719/1730 (99.4%)** | **1719/1730 (99.4%)** |

As of db5893b. 313 cases are skipped because they need features Trellis
leaves out or does differently on purpose (`position: static`,
`inline-block`, `display: contents`, intrinsic-size keywords, per-axis
overflow, `flex-wrap: balance`, `-webkit-box`); `trellis-case --all`
runs them anyway. The 11 failures are the documented consequence of
`display: block` meaning a column flex container (percentage heights
against a block, a fixed-height child shrinking inside a shorter block).

## Documents

- [docs/design.md](docs/design.md): architecture, API, tools, risks
- [docs/agents.md](docs/agents.md): writing Trellis UI (for coding agents)
- [docs/test-case-format.md](docs/test-case-format.md): JSON layout test cases
- [docs/known-issues.md](docs/known-issues.md)
