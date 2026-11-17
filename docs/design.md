# Trellis design

Trellis is a responsive layout library for new GNUstep and Cocoa
applications. It uses the CSS box model (Flexbox in v1, Grid in v1.1), with
exact CSS names and semantics. It is designed for apps written by coding
agents: layout is plain text, it is predictable from the code alone, and
a headless tool renders any screen to a PNG and a JSON frame dump, so an
agent can check its own work.

Status: v0.1 in progress. The engine and its test runner are in the repo
(`Source/Engine`, `Tools/trellis-case.m`). This document describes where
that code is going.

## Decisions (maintainer, 2026-11-13)

| Topic | Decision |
|---|---|
| Name | **Trellis**: `libTrellisEngine` (Foundation) and `libTrellis` (AppKit), class prefix `TR`. Private repo until release. |
| Licence | LGPL 2.1 or later, like the maintainer's other GNUstep libraries. |
| Toolchain | Modern clang, libobjc2, ARC, blocks, libdispatch. GCC is not supported. |
| Platforms | GNUstep (Linux first, then Windows/MSYS2) and native macOS AppKit, from the same source. |
| v1 scope | Flexbox, inline style strings, a typed ObjC API, container queries, `trellis-render` (PNG + JSON), `trellis-lint`. |
| v1.1 | CSS Grid on the same box tree and the same measuring. **An early implementation landed on 2026-11-13** (TRGrid.m; see agents.md for the supported subset). |
| Authoring | Typed ObjC API plus inline CSS declaration strings; `.trellis` layout files (markup plus scoped CSS) approved on 2026-11-13, built on the typed API. |
| Apple testing | project Macs; the conformance maintainer owns the macOS build. |

## 1. Survey

**Yoga** (Meta, MIT, C++ with a C API). This is the Flexbox engine behind
React Native. It is mature and fast, and its `gentest` fixtures, generated
from Chrome, are a good conformance source. Where Yoga departs from CSS:
- defaults are `flex-direction: column`, `position: relative`, border-box
  and `flex-shrink: 0`;
- there's no automatic minimum size;
- it has Flexbox only, with no Grid.

It needs a C++ toolchain. That's fine on Linux and macOS, but it means a
second runtime (libc++/libstdc++) in every GNUstep app.

**Taffy** (DioxusLabs, MIT, Rust). Block, Flexbox and Grid, each close to
the spec, used by Bevy, Zed's GPUI, Lapce and Slint. It has the best
coverage of any embeddable engine, but it brings a Rust toolchain and a C
FFI shim into a project packaged by Objective-C people, on every target
including MSYS2.

**Clay** (C, a single header of about 2k lines, zlib). Immediate-mode
"fit / grow / fixed" sizing that rebuilds the layout every frame. It shows
how few primitives most UI needs, but it isn't CSS, so agents can't bring
their CSS knowledge, and its immediate-mode model fits a retained NSView
tree poorly.

**Renaissance** (GNUstep, LGPL, Nicola Pero, about 2002–2008). XML GUI
markup with `GSAutoLayout` boxes (hbox/vbox, with expand and alignment
flags) and `GSAutoLayoutGrid`, which handles row and column spans. It
proves that text-described box layout works on GNUstep and Cocoa from one
source, and Trellis is its spiritual successor. Its layout vocabulary is
its own, though, not CSS, and it predates container queries, baselines and
min-content sizing.

**libs-gui today** (master 662f890, 2026-11-10):
- **Auto Layout:** a Cassowary port under `Source/GSCS*.m` (Tableau,
  LinearExpression, Strength and others), with `GSAutoLayoutEngine.m` at
  1443 lines, `GSAutoLayoutVFLParser.m`, `NSLayoutConstraint.m` (757
  lines) and `NSAutoresizingMaskLayoutConstraint.m`.
- **NSView** reaches it through `_layoutEngine`, which goes via the window,
  and `layoutSubtreeIfNeeded` (`Source/NSView.m` ~5374–5530).
- **`NSStackView.m`** (977 lines) and **`NSGridView.m`** (1240 lines) don't
  use the constraint engine. Each computes frames itself
  (`-_layoutViewsWithOrientation:` and `-_refreshCells`, which call
  `setFrame:`), and hugging and clipping priorities are stored but mostly
  advisory.
- **ChangeLog:** both arrived in 2020–2021 (Gregory Casamento), mainly so
  that xib files decode.

Conclusion: GNUstep has enough Auto Layout to load modern nibs, but it isn't
a foundation to design new UI on. That is what Trellis is for.

## 2. Engine: write our own (done)

**Recommendation, now implemented:** an in-house, Foundation-only
Objective-C/C engine (`TRLayout.m`, about 900 lines), following CSS
Flexbox section 9 directly. Measuring uses Yoga's model
(Undefined/Exactly/AtMost).

| | Own engine (chosen) | Vendor Yoga | Vendor Taffy |
|---|---|---|---|
| CSS fidelity | CSS defaults and auto min-size, by design | Yoga defaults; no auto min-size | Best |
| Grid | We write it (v1.1) | Never | Included |
| Toolchain | clang + Foundation only | C++ runtime | Rust + FFI on every target |
| Licence | LGPL, ours | MIT (compatible) | MIT (compatible) |
| Debuggability for agents | One ObjC file, readable | C++ | Rust |
| Risk | Spec edge cases; mitigated by WPT and Yoga suites | Low | Packaging |

Grid slots in later as a second algorithm, called from `TRLayoutNode` when
`display: grid`. It uses the same `TRNode` tree, measure blocks, cache and
rounding, so nothing in the view layer changes.

**Conformance sources:**
- **Yoga gentest fixtures** (MIT): HTML with expected Chrome frames,
  converted to our JSON (`box-sizing: border-box` on every node).
- **WPT css-flexbox reftests** (3-clause BSD): only the ones expressible as
  boxes plus Ahem text.

The conformance maintainer imports both, keeps their attribution, and reports
pass rates. The format is in `docs/test-case-format.md`.

## 3. Architecture

```
 .trellis file ──► TRLoader ─┐
 inline strings ─► TRStyle ──┼─► TRNode tree ──► TRLayout (flex; grid in v1.1)
 typed ObjC API ─────────────┘        ▲                │ frames
                                      │ measure        ▼
                     TRBoxView / leaf NSViews ◄── frames applied to real NSViews
                                      │
                     trellis-render ──┴──► PNG + frames.json ──► trellis-lint
```

- **Engine** (`libTrellisEngine`, Foundation only):
  - `TRStyle`: the parsed CSS properties;
  - `TRNode`: the box tree, measure and baseline blocks, a cache, and
    results;
  - `TRLayout`: the algorithm.
  - It builds the same way on GNUstep and Apple: `GNUmakefile` and
    `Makefile.macos`.
- **Views** (`libTrellis`, AppKit, with no GNUstep-only calls):
  - `TRBoxView` is an NSView container that owns a `TRNode` per subview.
  - Leaves are ordinary NSControls, measured through `intrinsicContentSize`
    where it exists, `-[NSCell cellSizeForBounds:]` for cell-based
    controls, and `sizeToFit` as a last resort. Text fields measure with
    `NSStringDrawing` at the proposed width.
  - Themes draw controls exactly as before; Trellis only sets frames.
  - Relayout happens in `-resizeSubviewsWithOldSize:` and
    `-setFrameSize:`. A `TRBoxView` is an ordinary view to its superview,
    so it lives inside autoresizing-mask or Auto Layout parents. Its
    `intrinsicContentSize` is its laid-out size.
- **Optional, later:** a state/diff layer (a `render` method that returns a
  lightweight tree, diffed onto real views). This is out of v1 scope.

## 4. API

### Typed

```objc
TRBoxView *row = [TRBoxView boxWithStyle: @"flex-direction: row; gap: 8px; align-items: center"];
[row addSubview: icon    style: @"width: 24px; height: 24px"];
[row addSubview: title   style: @"flex: 1"];          // NSTextField, measured
[row addSubview: button];                             // NSButton, intrinsic size

row.style.padding = TRPx(12);                         // typed setters exist for every property
[row.style setValue: @"space-between" forProperty: @"justify-content" error: NULL];
```

Engine-only use (tests, and non-AppKit renderers):

```objc
TRNode *root = [TRNode nodeWithStyle: @{@"width": @320, @"flexDirection": @"column"}
                            children: @[ [TRNode nodeWithStyle: @"height: 44px"],
                                         [TRNode nodeWithStyle: @"flex: 1"] ]];
[root layoutWithAvailableSize: TRSizeMake(NAN, 480)];
root.children[1].layoutFrame;   // {0, 44, 320, 436}
```

### Inline declarations

These are the same parser and the same names as CSS. There are no
selectors and no cascade. Shorthands are supported (`flex`, `margin`,
`padding`, `inset`, `gap`, `border`, `flex-flow`, `place-*`).
Non-layout declarations (`background-color`, `color`, `font-size`,
`border-radius`, …) are kept for the view layer. An unknown property
name is an error, so typos fail loudly.

### Container queries

A box can declare itself a query container, and descendant styles can carry
conditional blocks. These are evaluated against the container's own inner
width before each layout pass:

```objc
TRBoxView *card = [TRBoxView boxWithStyle: @"container-type: inline-size; flex-direction: column; gap: 12px"];
[card addConditionalStyle: @"flex-direction: row" when: @"width >= 560px"];
```

In `.trellis` files this is a real `@container (min-width: 560px) { … }`
block.

### Example screens

The full sources go in `Examples/TrellisDemo` as `.trellis` files. Below
are the typed-API equivalents and the result at two widths.

**(a) AIManager-style ask detail**

```objc
TRBoxView *ask = [TRBoxView boxWithStyle:
  @"container-type: inline-size; flex-direction: column; padding: 16px; gap: 12px"];
TRBoxView *header = [TRBoxView boxWithStyle: @"flex-direction: row; gap: 8px; align-items: baseline"];
[header addSubview: kindBadge style: @"flex: none"];
[header addSubview: titleLabel style: @"flex: 1; font-size: 15px"];   // wraps
[header addSubview: ageLabel style: @"flex: none; color: #888"];
[ask addSubview: header];
[ask addSubview: bodyText style: @"flex: 1; min-height: 80px"];        // NSTextView in a scroll view
TRBoxView *options = [TRBoxView boxWithStyle: @"flex-direction: column; gap: 6px"];
[options addConditionalStyle: @"flex-direction: row; flex-wrap: wrap" when: @"width >= 560px"];
for (NSButton *b in optionButtons) [options addSubview: b style: @"flex: 1 1 160px"];
[ask addSubview: options];
```

| 420 px wide | 760 px wide |
|---|---|
| The header row wraps the title; the option buttons stack full-width. | The option buttons sit side by side on one row (`flex: 1 1 160px`, wrapping if more than four). |

**(b) Settings form.** Each row is `label | control`, and the labels share
a column width without a grid:

```objc
TRBoxView *form = [TRBoxView boxWithStyle: @"container-type: inline-size; flex-direction: column; gap: 10px; padding: 20px"];
for (NSArray *pair in rows) {
  TRBoxView *r = [TRBoxView boxWithStyle: @"flex-direction: column; gap: 4px"];
  [r addConditionalStyle: @"flex-direction: row; align-items: baseline; gap: 12px" when: @"width >= 480px"];
  [r addSubview: pair[0] style: @"flex: 0 0 140px; text-align: right"];  // label
  [r addSubview: pair[1] style: @"flex: 1; max-width: 360px"];           // control
  [form addSubview: r];
}
```

| Below 480 px | 480 px and up |
|---|---|
| Each label sits above its control (a column). | A 140 px right-aligned label column with baselines aligned. Grid in v1.1 makes the label column content-sized. |

**(c) Toolbar row**

```objc
TRBoxView *bar = [TRBoxView boxWithStyle: @"flex-direction: row; align-items: center; gap: 6px; padding: 4px 8px"];
[bar addSubview: back]; [bar addSubview: forward];
[bar addSubview: search style: @"flex: 1 1 200px; min-width: 120px; max-width: 480px"];
[bar addSubview: spacer style: @"flex: 1"];
[bar addSubview: share]; [bar addSubview: menu];
[share.trellisStyle setValue: @"none" forProperty: @"display" error: NULL]; // hidden below 500px via @container
```

## 4a. Not CSS: where Trellis departs from the browser

Agents must not assume browser behaviour in these cases:

| Topic | Browser CSS | Trellis |
|---|---|---|
| Default `display` | `inline` / `block` by element | `flex` for every box |
| `display: block` | block flow | a **column** flex container (`align-items: stretch`) |
| `box-sizing` | `content-box` | **`border-box`** |
| Block and inline flow, floats, tables | yes | no; boxes are flex (v1) or grid (v1.1) containers |
| `position: absolute` | relative to the nearest *positioned* ancestor | relative to the **parent's** padding box |
| Default `position` | `static` | `relative` (insets offset the box) |
| Unitless lengths | invalid, except 0 | accepted as px; `trellis-lint` warns |
| Unknown property names | ignored | **an error** |
| Selectors and cascade | yes | inline styles have none; `.trellis` files have file-scoped type, class and id selectors only |
| Units | many | `px`, `%` and `auto` (plus `fr` in v1.1) |

## 5. The agent loop: trellis-render and trellis-lint

```
trellis-render [--width W] [--height H] [--widths 360,560,900]
               [--theme NAME] [--scale 1|2] [--sample Name.sample.json]
               [--png out.png] [--json out.json] [--outlines]
               (Screen.trellis | --class TRDemoAskView --bundle Demo.bundle)
```

- **Isolation (fail closed).** It runs offscreen under a private Xvfb display
  and never touches the user's GNUstep defaults:
  - On GNUstep, `NSHomeDirectory()` comes from `$GNUSTEP_HOME`, falling
    back to the passwd entry, and **ignores `$HOME`**. `GNUstep.sh` also
    ends by unsetting `GNUSTEP_HOME`.
  - So `scripts/run-headless.sh` exports `GNUSTEP_HOME` (and `HOME`) to a
    throwaway directory *after* sourcing GNUstep.sh, and starts Xvfb on a
    free display number.
  - Before `NSApplication` starts, the tool checks that `NSHomeDirectory()`
    and the user Library path (where NSUserDefaults lives) both resolve
    inside that directory. If not, it exits with status 3 before any GUI
    code runs.
  - It refuses to run against `:0` or the user's own display.

  This closes the gap that wrote into a developer's real defaults on 2026-11-11.
  On macOS it uses `-[NSView cacheDisplayInRect:toBitmapImageRep:]` with
  no window on screen.
- With `--widths`, it writes one PNG and one JSON per width
  (`out-360.png` and so on).
- `--outlines` draws box outlines, padding and gaps over the controls: the
  "inspector" view.

**frames.json:**

```json
{
  "trellis": "0.1", "source": "AskDetail.trellis", "theme": "Adwaita",
  "viewport": {"width": 420, "height": 640, "scale": 1},
  "root": {
    "id": "ask", "class": "TRBoxView", "x": 0, "y": 0, "width": 420, "height": 640,
    "style": "container-type: inline-size; flex-direction: column; padding: 16px; gap: 12px",
    "container": {"matched": []},
    "children": [
      {"id": "title", "class": "NSTextField", "x": 16, "y": 16, "width": 300, "height": 38,
       "intrinsic": {"width": 520, "height": 19}, "text": "Approve the rc2 tag?",
       "lines": 2, "clipped": false}
    ]
  },
  "lint": [
    {"rule": "clipped-text", "id": "age", "message": "text needs 64px, has 50px"}
  ]
}
```

**trellis-lint** works on the same tree, and will also run as a build step
for `.trellis` files. Its rules:

| Rule | What it checks |
|---|---|
| `clipped-text` | Text whose measured size exceeds its frame. |
| `undersized` | A control smaller than its intrinsic size. |
| `overlap` | Siblings whose frames overlap without absolute positioning. |
| `overflow` | Content beyond the container (`contentSize > frame`) with `overflow: visible`. |
| `offscreen` | A box outside the viewport. |
| `unitless` | A nonzero length written without a unit. |
| Bindings (`.trellis` files) | Unknown ids, outlets or actions on the owner class. |

## 6. Layout files (`.trellis`), approved on 2026-11-13

```html
<!-- AskDetail.trellis, owner: AIAskDetailController -->
<column id="ask" class="card">
  <row class="header">
    <label id="kind" class="badge"/>
    <label id="title" class="title" wraps="yes"/>
    <label id="age" class="muted"/>
  </row>
  <scroll class="body"><text id="body" editable="no"/></scroll>
  <row id="options">
    <button title="Approve" action="approve:"/>
    <button title="Reject" action="reject:"/>
  </row>
</column>
<style>
  .card    { container-type: inline-size; padding: 16px; gap: 12px; }
  .header  { gap: 8px; align-items: baseline; }
  .title   { flex: 1; font-size: 15px; }
  .muted   { color: #888; }
  #options { flex-direction: column; gap: 6px; }
  #options > button { flex: 1 1 160px; }
  @container (min-width: 560px) { #options { flex-direction: row; flex-wrap: wrap; } }
</style>
```

- **Elements:**
  - `column`, `row` and `box` are TRBoxViews;
  - `scroll` is an NSScrollView with a box as its document view;
  - `label`, `field`, `text`, `button`, `checkbox`, `popup`, `image`,
    `slider`, `progress` and `separator` map to the standard controls;
  - `<view class="MyView">` is a custom NSView subclass.

  Attributes set control properties (`title`, `placeholder`, `state`,
  `editable`); `style="…"` is inline CSS.
- **CSS scope:** type, class and id selectors, plus the child combinator
  `>`, all scoped to the file. There's no cascade between files and no
  inheritance except `direction`, `color` and `font-*`. Specificity
  follows CSS.
- **Binding:** `id` matches an outlet (an ivar or property) on the owner,
  set by KVC at load time. `action="approve:"` targets the owner. A
  mismatch is a load error, and `trellis-lint --owner Class.h` catches it
  at build time.
- **Loading:**
  - `[TRLoader loadFile:owner:error:]` returns the root TRBoxView.
  - Errors give `file:line:col`.
  - Files are loaded at runtime, which allows hot reload, and there's no
    code generation.
  - `trellis-render` renders a file with `Name.sample.json` content and no
    app build.
- **Dynamic UI** (lists, conditional panels) uses the typed API directly, or
  `<template id="row">`, cloned by code.

## 7. Risks

| Risk | Mitigation |
|---|---|
| **Text measurement differs** between GNUstep (cairo, FreeType) and Apple (CoreText), so frames differ by a few px and wrap points move. | Tests use Ahem-style measurers and never real fonts. Screens are designed with slack (`flex: 1`, min/max). Lint checks clipping per platform. Demo screenshots are taken on both. |
| **Live-resize performance.** A relayout per resize event, with a NSStringDrawing measurement per text leaf. | A measurement cache keyed on constraints (16 entries per node, cleared only on dirty; the containing-block size is left out of the key unless the node uses percentages). Non-wrapping controls are memoized on their content. **Measured** with `obj/trellis-bench`: 521 nodes with 320 text leaves takes 0.42 ms for the first layout and 0.25 ms per resize step with about 1.4 measure calls per leaf. 1301 nodes takes 0.6 ms per step, well inside 16.7 ms at 60 Hz. **macOS** (Apple M4, Apple clang 17, `build/trellis-bench`, median of 5 runs at 92926dc): 521 nodes 0.30 ms first layout, 0.19 ms per resize step; 1301 nodes 0.71 ms first layout, 0.46 ms per step; the same measure-call counts as Linux (2400 / 6000 first, ~1.4 calls per leaf per step), so the cache behaves identically. A cold first process run is slower (1.5 ms first layout). |
| **Baselines.** NSControl baselines aren't exposed uniformly (`firstBaselineOffsetFromTop` is Apple 10.11+ only and missing on GNUstep). | The leaf adapter computes it from the cell's title rect and font ascender. Falls back to the bottom edge. |
| **Right-to-left.** | `direction: rtl` is implemented in the engine (it flips main and cross axes per CSS). The view layer takes the default from `NSApp.userInterfaceLayoutDirection` on Cocoa (GNUstep has none, so ltr), and a box that starts its own layout tree (in a split pane or a scroll view) inherits the direction of the node holding it; `dir="rtl"` in markup sets `direction`. NSSplitView panes are not mirrored. Logical properties (`margin-inline-start`, `padding-inline`, `inset-inline-end`, `inline-size` and so on) map to physical edges by each box's own direction, horizontal writing only. |
| **Scroll views.** | `overflow: auto/scroll` on a box makes the view layer wrap it in an NSScrollView. The document view is laid out with an unconstrained main axis; `contentSize` comes from the engine. |
| **Coexisting with autoresizing masks and Auto Layout on Apple.** | TRBoxView is a leaf to everyone outside it. It sets `translatesAutoresizingMaskIntoConstraints = YES` on its subviews, and exposes `intrinsicContentSize` and `invalidateIntrinsicContentSize` when its content changes. We don't mix constraints inside a TRBoxView. |
| **Departures from browser CSS.** | `display` defaults to flex, with no block or inline flow. Absolute children are placed against their parent box. Documented, and checked by conformance. |
| **Maintainer load of a second layout system.** | Separate library, Foundation-only core, conformance suite. |

## 8. Decided questions (project lead, 2026-11-13; the maintainer may override)

1. `display: block` is a column flex container with `align-items: stretch`.
   **Implemented.**
2. `box-sizing` defaults to `border-box`, as a deliberate departure from
   CSS. WPT imports set `content-box` explicitly. **Implemented.**
3. No subgrid in v1.1. Grid comes first; subgrid in v1.2 if form label
   columns need it (`max-content` tracks cover most of that).
4. Windows/MSYS2 comes after v1.
