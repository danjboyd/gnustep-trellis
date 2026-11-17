# Changelog

Trellis follows semantic versioning once 1.0 ships; before that, a minor
version may change the API listed in docs/api.md, and says so here.

## Unreleased

- **Changed (layout):** a `position: static` box is no longer a containing
  block. Its absolutely positioned children are placed against the nearest
  positioned ancestor's padding box (or the layout root's), as in CSS and
  Yoga 3. Insets and percentages use that box, and auto insets keep the
  static position in the real parent. Boxes default to `position: relative`,
  so layouts that never say `static` don't change. The 128 Yoga
  `position: static` cases now run by default: conformance is 3280/3280. See docs/migration-0.8.md.
- **Fixed:** in grid row sizing, an item with `aspect-ratio`, a stretched
  or definite width and a percentage height now gets its height from the
  aspect ratio, as CSS does: the percentage counts as `auto` while the rows
  are sized. Before, the row stayed at the grid's height
  (WPT grid-item-aspect-ratio-justify-self-001).
- **Fixed:** `trellis-render` and TrellisPreview dumps mark a view hidden
  when its node is (`hidden` or `display: none`), including a parked split
  pane's subtree.

## 0.7.1 (2026-11-17)

Fixes, no API or layout-rule changes: split panes honour `display: none`,
TrellisPreview's exit codes and appearance check, and a migration guide
(docs/migration-0.7.md). Conformance 3152/3152 on Linux and macOS.

- **Fixed:** a split pane whose resolved style is `display: none` (for
  example from a container query) leaves the split like a hidden pane, and
  comes back when the style changes; it used to keep its width. Frame dumps
  (trellis-render, TrellisPreview) mark hidden panes `"hidden": true`.
- **Fixed (TrellisPreview):** `--snapshot` / `--export-json` exit 1 when
  the spec or its sample doesn't load (the snapshot of the error message is
  still written); `--appearance` takes only `light` or `dark` (exit 2
  otherwise). Its frames JSON now carries each node's `style`, `overflow`
  and matched `container` conditions, like trellis-render's.

- docs/migration-0.7.md: what changed for a screen from 0.5.x to 0.7 and
  what to check, with a fixture (Tests/Reference/migration.trellis) and
  `make check-migration`.

## 0.7.0 (2026-11-17)

Changes grid layout behavior (a minor version, so pins on 0.6.x don't
move): space from items spanning several tracks follows CSSWG #3648. No
API changes. Conformance 3152/3152 on Linux and macOS (WPT 34bdce1).

- The macOS build uses current AppKit names (no deprecation warnings);
  GNUstep is unchanged.
- Tooling: `make check-reference` (GNUmakefile and Makefile.macos)
  replays golden frame dumps from both platforms through the engine and
  checks that a changed geometry value is caught; trellis-render and
  TrellisPreview dumps record `measured` sizes; WPT refreshes are
  reviewed with Tests/Conformance/tools/snapshot_diff.py.
- **Behavior change (grid):** a spanning item's extra space now goes to
  the spanned tracks that can still take it before any track grows past
  its growth limit (CSSWG #3648, CSS Grid 2 12.5.1 "distribute space to
  non-affected tracks"). An empty intrinsic track next to a spanning item
  stays at its content size instead of absorbing the overflow. Matches
  WPT 34bdce1's revised grid-gutters-and-flex-content-001. Two older WPT
  cases that predate the change are listed in
  Tests/Conformance/upstream-stale.json.

## 0.6.0 (2026-11-17)

Changes layout behavior (a minor version, so pins on 0.5.x don't move):
children of `display: block` no longer flex, and percentage heights
resolve only against definite heights, as in CSS. Adds right-to-left
support in the view layer (`dir="rtl"`, logical properties that follow
`direction`) and `-[TRBoxView inheritedLayoutDirection]`; nothing is
removed from docs/api.md. Conformance: 2977/2977.

- **Behavior change:** children of `display: block` never grow or
  shrink, and their `flex-basis` is ignored, as in CSS block flow. A
  `height: 100px` child of a 50px block now overflows instead of being
  squeezed. Use a `<column>` (or `display: flex; flex-direction: column`)
  where children should flex. trellis-lint warns on `flex`, `flex-grow`,
  `flex-shrink` and `flex-basis` on a block's children.
- **Behavior change:** a percentage height resolves only against a
  definite height (css-flexbox 9.8): a fixed height, a stretched item,
  or a flexed item of a column whose height is definite. Inside an item
  aligned `flex-start` in a row, or an item of an auto-height column,
  `height: 50%` now acts as `auto` (it took half of the laid-out height).
  With these two, every conformance case that runs passes (2977/2977).
- **Fixed:** an absolutely positioned grid item now takes `justify-self`
  and `align-self` (or the grid's `justify-items` / `align-items`) in an
  axis whose insets are both auto, and its margins; both were ignored. A
  set inset still positions it as in CSS 2. WPT: with inline-grid cases
  enabled, wpt-grid passes 1383/1390 (was 1324).
- **Fixed:** logical properties follow `direction`: in a right-to-left box
  `margin-inline-start`, `padding-inline-start`, `border-inline-start`
  and `inset-inline-start` are the right edge (they were always the left).
  Each box maps them by its own direction, inherited when unset, and
  declaration order decides between a logical and a physical side
  (`margin-right: 5px; margin-inline-start: 10px`), as in CSS.
- **Added:** the shorthands `margin-inline`, `margin-block`,
  `padding-inline`, `padding-block`, `inset-inline` and `inset-block`,
  and the logical sizes `inline-size`, `block-size` and their `min-`/`max-`
  forms (horizontal writing only, so inline is the width).
- **Fixed:** `position: relative` offsets (`left`, `top`, ...) on grid
  items were ignored; they now move the item, against its grid area. With
  both `left` and `right` set, an rtl container uses `right`, in flex too.
- **Added:** `dir="rtl"` / `dir="ltr"` in markup, as in HTML (any other
  value is an error). A box in a split pane or a scroll view lays out with
  the direction around it; it was always ltr. On Cocoa the default follows
  `NSApp.userInterfaceLayoutDirection`. `-[TRBoxView
  inheritedLayoutDirection]` says which direction a box inherits.
- **Fixed:** `-[TRStyle declarationString]` writes logical sides back as
  logical sides, so a frame dump of an rtl screen reads back the same.
- `trellis-case` accepts a declaration string as a node's `style`, and
  no longer skips conformance cases that need logical properties
  (WPT: 4 more pass).

## 0.5.1 (2026-11-17)

Adds API (listed in docs/api.md, nothing removed): split panes that can
be hidden, keyboard resizing of split dividers, a `disabled` attribute
and `TRSetEnabled`; focus and accessibility fixes, new lint checks, a
Focus Order view in TrellisPreview, and linear-time markup parsing.

- **Fixed:** markup parsing was quadratic in the file's size (each
  element's line and column were counted from the start): 6,000 elements
  took 1.2 s to parse, now 19 ms, so TrellisPreview reloads big screens
  quickly. Load and layout were already linear (6,000 elements: about
  125 ms and 105 ms on Linux). `Tests/Engine/markup-scale.m` guards it.
- **Added:** keyboard resizing for `<split>`: the split is a Tab stop
  after its first pane (macOS: with full keyboard access); arrows move
  the divider 10pt (1pt with Option), Home/End go to the limits, `[`/`]`
  pick the divider. `TRSplitView.enabled` (and `disabled` on a split)
  stops dragging and the keyboard. A `TRKeyViewProvider` may list itself
  to be a Tab stop. TrellisPreview's focus order skips views that can't
  take focus.
- **Added:** `disabled` on a control, or on a container to disable every
  control in it (labels are left alone), and `TRSetEnabled(view, YES|NO)`
  in code; `"disabled"` in sample files. Disabled controls stay in the
  key-view loop (Tab skips them), so enabling one needs no relayout.
  trellis-lint: a bad value is an error; `disabled` on a label, text,
  image, spacer, separator or progress bar is a warning.
- **trellis-lint:** `tabindex` must be a whole number (error), and a
  positive one inside a `<template>` is a warning: every copy shares it,
  so the copies jump ahead of the rest of the screen.
- **TrellisPreview:** View > Focus Order (⌘K) numbers the controls in
  Tab order and links them; `--focus-order` for snapshots. Export Frames
  JSON adds `focusOrder` (each control's id, else its class).
- **Added:** split panes can be hidden: `hidden` on a `<split>` pane, or
  `-[TRSplitView setHidden:forPane:]` and `-isPaneHidden:`. The pane and
  its divider leave, the others take its space, and it comes back at the
  size it had; focus inside moves out. (Before, `hidden` on a pane was a
  load error.) A sample file's `"hidden"` works on panes too.

- **trellis-lint:** `unlabeled` now covers `<segmented>` (the group needs
  a name) and segmented items with no text; a `label-for` whose target is
  hidden while the label isn't is a warning. Markup tests gain
  `Tests/Markup/warn/` cases (lint must warn, not fail).
- **Fixed:** hiding the view that has keyboard focus (`hidden`,
  `-setHidden:forSubview:`, a container query) moves focus to the next
  view in the loop on Cocoa too; GNUstep already did.
- **Fixed:** while a text field was being edited, rebuilding the key-view
  loop put the field editor in it in place of the field (GNUstep).
- **Fixed:** scrolled content that hides or shows a view on its own
  layout now updates the outer box's key-view loop.

## 0.5.0 (2026-11-17)

Adds API (listed in docs/api.md, nothing removed): `<split>` resizable
panes, `<segmented>` controls, a `hidden` attribute and
`-setHidden:forSubview:`, per-side borders, and dashed, dotted and double
borders that paint as such.

- Dashed, dotted and double borders draw as such (they drew solid).
  `border: 2px none` now has no width, as in CSS.
- `hidden` attribute, `-[TRBoxView setHidden:forSubview:]` and
  `-isSubviewHidden:`, and `TRNode.hidden`: hide a view without touching
  its style, so showing it again needs no `display:`. A sample file's
  `"hidden"` uses it too (it used to set the view's own flag, which the
  next layout undid).
- On GNUstep, `AccentColor` and `LinkText` never resolve to a grey: with
  the default theme (whose selection colour is white) they drew white on
  white; they now fall back to a fixed blue. Adwaita and Gumdrop keep
  their own selection blue.
- Per-side borders: `border-top`, `-right`, `-bottom`, `-left` (and the
  logical `border-inline-*`/`border-block-*`) shorthands and the
  `border-<side>-style` longhands. Sides that differ draw separately
  (square corners). `border:`, `border-color:` and `border-style:` reset
  the sides.
- `<segmented>` and `TRSegmentedControl`: a segmented control with
  `<item>` children or `items=`, `tracking=one|any|momentary`, a
  selection by title in markup, code (`selectedTitles`) and sample files,
  sized so every label fits in the bold face too. A selection under
  `tracking="momentary"` is an error (AppKit keeps none).
- `<split>` and `TRSplitView`: resizable panes, sized from each pane's
  CSS (starting size, min/max, flex-grow), with divider positions kept
  under `autosave=` and readable and settable in code.

## 0.4.0 (2026-11-17)

Adds API (listed in docs/api.md, nothing removed): virtualized lists and
grids (docs/design-virtualization.md), CSS custom properties with
built-in theme tokens, layout transitions, rich text in labels, a
tutorial with a CI job, Preview export and appearance switching, and a
target-size lint.

- **Added:** `<virtual layout="list|grid">` and `TRVirtualBox`, a scroll
  view that builds views only for the items on screen (plus overscan):
  - each item is a copy of a `<template>`, reused from a pool per
    template; a template whose root has `grid-column: 1 / -1` takes a
    whole row (group headers);
  - items are measured when they come on screen, and scroll anchoring
    keeps the top item still through measures, inserts, removals and
    resizes;
  - Tab walks the visible items in order and scrolls the next one in past
    the edge (Shift-Tab too); the focused item is never recycled;
  - the box is a list or grid for accessibility, with the full count and
    columns, and each item records its index, row and column
    (`TRAccessibilityCollection`, `TRAccessibilityPosition`;
    NSAccessibility on Cocoa);
  - container queries inside items test the box's containers.
- **Added:** `TRVirtualLayout`, the window engine (Foundation only):
  item heights only, grid columns from the real grid engine.
- **Added:** `TRVirtualDataSource`, `-[TRBoxView heightForWidth:]`,
  `TRKeyViewProvider`, `TRApplyLeafStyle`,
  `+[TRLoader instantiateTemplateElement:ofDocument:error:]`.
- **Added:** sample files fill a virtual box (`items`, runs with
  `_repeat`, `{i}` / `{n}` / `{n:W}`, `scroll-to`); trellis-render and
  TrellisPreview dump and lint its visible items.
- **trellis-lint:** checks `<virtual>` (template children, `template=`,
  `layout=`); duplicate ids are counted per template.
- **Fixed:** a template whose root is a control now gets its text style
  (it had none).
- **Measured** at 10,000 items on Linux: the engine scrolls at 0.24 ms
  per viewport step (list) and 0.67 ms (grid with headers), flat at
  100,000, with +5 MB peak RSS against +89 MB for one ordinary tree of
  the same rows; real views in a 900x800 window, 0.95 ms (list) and
  2.8 ms (grid) per step with at most 47 and 133 views alive.
- **Tests:** Tests/Engine/virtual-layout.m (`make check`),
  Tests/View/virtual-box.m and virtual-bench.m (`make check-gui`, zombies
  on), `trellis-bench --virtual N`.
- **Dogfood:** dogfood/work/Work-virtual.trellis, the Work wall with
  2,000 made-up agents.
- **Keyboard on Cocoa:** where AppKit can't Tab to an item's controls
  (buttons without full keyboard access), Tab and Shift-Tab step from the
  focused item, one at a time (found by the macOS check; a test simulates
  it on Linux).
- **Added:** CSS custom properties in .trellis files: `--name: value`
  inherits down the element tree, and `var(--name)` /
  `var(--name, fallback)` works in any value (custom properties may use
  others; a cycle is an error). An undefined `var()` is an error at the
  element, so trellis-lint reports it. A custom property set inside an
  `@container` block applies within it.
- **Added:** built-in tokens, defined in every document: font sizes,
  control and field heights, scroller width (from the running theme via
  `TRUpdateThemeTokens`, at each load), spacing and radius steps, and
  aliases of the system colours (`--tr-accent`, `--tr-muted`, ...).
  Tests/Engine/custom-properties.m runs in `make check`.
- **Changed:** `-[TRMarkupDocument declarationsForElement:]` returns
  declarations with custom properties resolved, and TRStyle ignores
  `--name` declarations set from code.
- **Added:** the `touch-target` lint (WCAG 2.2, 2.5.8): a control under
  24x24 px whose 24 px circle reaches another control in the same
  scroller is a warning. Frame dumps mark controls `interactive`.
  Tests/Engine/lint-targets.m in `make check`; no finding in any example
  or dogfood screen at 340 and 900 px.

- **TrellisPreview:** View > Light / Dark Appearance (GNUstep: the
  Adwaita colour scheme, set for the process before the theme loads, so
  switching relaunches Preview with the same file and size; macOS: the
  window's appearance), and File > Export PNG… / Export Frames JSON…
  (trellis-render's `--json` document, with lint). Headless flags
  `--export-json` and `--appearance`. Tests/View/preview-export.sh in
  check-gui. On macOS the snapshot and JSON resolve colours under the
  chosen appearance, with the window background drawn in (found by the
  macOS check).
- **Tests:** virtual-box.m waits for focus to leave a sentinel before
  the next Tab (the hand-off is deferred; on Cocoa it could take more than
  one run-loop pass once the list scrolls). Found and fixed by the macOS
  check.

- **Docs:** docs/tutorial.md, "Build your first Trellis app": a small app
  with a layout, an owner, lint, renders at two widths, a container query
  and a smoke test. `scripts/check-tutorial.sh` extracts its files and
  steps and runs them; CI runs it on every push (including tutorial-only
  edits).

- **Added:** rich text in `<label>` and `<text>`: `<b>`/`<strong>`,
  `<i>`/`<em>`, `<code>`, `<br/>`, and links. `<a action="sel:"
  href="...">` sends the action to the owner with the label as sender
  (`clickedLink` is the href; trellis-lint checks the action); a bare
  http(s)/mailto href opens. The runs follow the label's style, and the
  view is a `TRRichLabel`. `-[TRMarkupElement content]` gives text and
  children in order. Tests/View/rich-text.m (check-gui).

- **Added:** layout transitions, opt-in: `-tr-layout-transition: 200ms`
  (with `linear` / `ease-in-out`, or `none`) on a box animates its
  subviews, and nested boxes', to their new frames after content or style
  changes. Resizes don't animate, first appearances don't, a change
  mid-way starts from the current frames, and reduced motion (Cocoa's
  setting, `TRReduceMotion` / `TRELLIS_REDUCE_MOTION=1` on GNUstep, or
  `+[TRBoxView setReducesMotionOverride:]`) turns it off.
  `-layoutTrellisAnimated` and `isAnimatingLayout` on TRBoxView, and
  for tests a fixed clock (`+setAnimationTimeOverride:`) with
  `-stepLayoutAnimation`, so animations step deterministically however
  slowly timers fire.
  Tests/View/layout-transition.m (check-gui, zombies on).

## 0.3.0 (2026-11-16)

Adds API (listed in docs/api.md, nothing removed):

- **Added:** `-tr-warning-background` and `-tr-warning-text`, a soft
  peach and dark brown pair that stays light in both appearances, like
  `Mark`/`MarkText`.
- **Added:** `<button bordered="no">` for flat, title-only buttons, and
  `color:` on buttons (it colours the title). Their cell,
  `TRFlatButtonCell`, draws the title itself: the Adwaita theme draws
  push-button titles in its own colour. trellis-render reports a flat
  button's real title colour to the contrast lint.
  Tests/View/flat-chips.trellis checks both in appearance.sh.
- **Fixed (Cocoa):** fixed CSS colours (hex, `rgb()`) are made in sRGB,
  as CSS defines them; they were generic RGB and drew slightly shifted.
  GNUstep is unchanged.
- **Dogfood:** the desk spec uses both, and pins its decision bar.

## 0.2.3 (2026-11-16)

No API changes.

- **Fixed:** a flex item's definite cross size is clamped by its min/max
  before its content is measured. A column item with `width: 100%;
  max-width: 920px` measured its height at the full width, so a wrapping
  row inside it came out a row short and overflowed. Two engine cases.
- **Tests:** Tests/Markup/run.sh takes `LINT=`, and appearance.sh and
  scroll-container-query.sh take `RENDER=`, so the macOS job can point
  them at its build.
- **Dogfood:** dogfood/desk, the triage desk shell and four cards.

## 0.2.2 (2026-11-16)

No API changes.

- **Fixed:** a hang on GNUstep (0.2.0 to 0.2.1). The managed key-view loop
  was a closed ring, and GNUstep's `-nextValidKeyView` walks a chain until
  it finds a view that can become key, nil or its start. So when every
  view in the ring was hidden or disabled, and the search started outside
  it, the search never ended. On GNUstep the chain is now open and wraps
  through a private sentinel view, which leads back in only while some
  member can take focus. On Cocoa the loop stays a closed ring, as in 0.2.1: AppKit's
  search stops on its own, and overriding the key-view getters there
  leaves dangling back-pointers (found by the macOS check). Views that
  leave the loop are unlinked, and
  `managesKeyViewLoop = NO` unlinks what Trellis linked.
  Tests/View/key-view-hang.m (KEYHANG in `make check-gui`) covers all
  hidden, all disabled, a hidden box and all `display: none`, with an
  alarm guard. On GNUstep, walking raw `-nextKeyView` now passes through
  the sentinel (a view outside the tree) between the last view and the
  first; Tab (`-nextValidKeyView`) skips it.

## 0.2.1 (2026-11-16)

No API changes.

- **Fixed:** a crash (use-after-free) when a box tree was freed with a
  layout still queued. The deferred layout now goes through a helper
  that holds the box weakly, and a box being freed schedules nothing.
  This affects v0.1.0 through v0.2.0 on GNUstep, where the delayed
  performer doesn't keep a deallocating box alive.
  Tests/View/dealloc-pending-layout.m (DEALLOC in `make check-gui`, run
  with NSZombieEnabled) covers it.
- **Fixed:** `MarkText` is black: `Mark` is a light highlight in both
  appearances, and MarkText used to follow the text colour, so it turned
  near-white on yellow in dark. Tests/View/mark.trellis covers it in
  appearance.sh.
- **Lint:** `overflow` allows a measured (text) leaf to stick out of its
  parent by up to 1 px, the pixel rounding Trellis shares with Yoga.

## 0.2.0 (2026-11-16)

Adds API (listed in docs/api.md, nothing removed): keyboard focus order,
accessibility attributes, dev hot reload.

- **Added:** opt-in dev hot reload. With `TRELLIS_HOT_RELOAD=1`, the
  `TRHotReload` default or `+[TRLoader setHotReloadEnabled:]`, boxes
  loaded from files are rebuilt in place when the file changes. Outlets
  and actions are bound again, and the owner gets `-trellisDidReload:`.
  A broken edit keeps the old layout. `make hot_reload=no` compiles it
  out.
- **Fixed:** `aspect-ratio` on a root box. A definite width or height
  now gives the other size through the ratio. Sizes are floored at
  padding plus border and clamped by min/max first, and an empty root
  with both sizes auto starts from its minimum height. Added
  `aspect-ratio: auto <ratio>`, whose ratio applies to the content box
  even under border-box. WPT css-sizing goes from 10/21 to 20/21.
- `display-table` cases are skipped by default.

- **Added:** accessibility basics. `a11y-label`, `label-for` and
  `role="group|none"` in markup, mapped to NSAccessibility on Cocoa and
  recorded on GNUstep (whose AppKit has no accessibility setters yet).
  trellis-lint warns `unlabeled` and rejects a `label-for` without a
  target or an unsupported `role`. The demos and dogfood proposals now
  label every control.
- **Added:** keyboard focus order. The outermost TRBoxView links its
  controls into a nextKeyView loop in document order after every layout,
  skipping hidden ones (container queries included); `tabindex="N"`
  overrides it and `tabindex="-1"` leaves a control out. API:
  `managesKeyViewLoop`, `-recalculateTrellisKeyViewLoop`, `firstKeyView`,
  `TRSetTabIndex`/`TRTabIndex`.
- **Fixed:** container queries inside a `<scroll>` now test the nearest
  container outside the scroller. They used to test the scroller's
  content box, so a classic, space-taking scroller shifted the
  breakpoint (Gumdrop at 520px; reported by a pilot app).

## 0.1.1 (2026-11-16)

Dark appearance and themes. In Dark (macOS) or a dark GNUstep theme, a
fixed CSS background kept its light colour while unstyled text turned
light, so text vanished.

- **CSS system colours:**
  - `Canvas`, `CanvasText`, `Field`, `FieldText`, `ButtonFace`, `ButtonText`,
    `ButtonBorder`, `GrayText`, `Highlight`, `HighlightText`, `SelectedItem`,
    `SelectedItemText`, `AccentColor`, `AccentColorText`, `LinkText`, `Mark`
    and `MarkText`;
  - plus `-tr-window-background`, `-tr-separator`, `-tr-secondary-text` and
    `-tr-error`.

  They resolve to AppKit's dynamic colours at draw time, so they follow the
  appearance and the GNUstep theme.
- **trellis-lint `colour-pair`:** warns about a fixed background with text
  that follows the system, or a fixed text colour over a system background.
- **trellis-render:** `--appearance light|dark` (DarkAqua on macOS,
  Adwaita's colour scheme on GNUstep). It passes `-DefaultsKey value`
  through, and dumps the resolved colours (`background`, `textColor`,
  `windowBackground`).
- **Render lint `low-contrast`:** text under 3:1 against its resolved
  background.
- **Specs:** the demos and dogfood specs now use system colours. The
  Tickets specs' selected rows use HighlightText. The dogfood reply text
  view no longer collapses.
- **`make check-gui`** adds Tests/View/appearance.sh, which renders every
  screen in light and dark and checks a bad fixture is caught.

## 0.1.0 (2026-11-16)

The first versioned release (private).

- **Engine (libTrellisEngine, Foundation only):**
  - CSS Flexbox and CSS Grid layout, with container queries.
  - Absolute positioning against the parent, physical and logical
    alignment keywords, `safe`/`unsafe` overflow alignment, and
    `aspect-ratio`.
  - Pixel-grid rounding.
  - Defaults: `border-box`, and `display: block` is a column flex container
    (see docs/agents.md section 4).
- **Grid:**
  - explicit and implicit tracks, including implicit tracks before the
    explicit grid;
  - `repeat()` with auto-fill/auto-fit, whose count also comes from
    min/max sizes;
  - `minmax()`, `fit-content()`, fr sizing (indefinite and min/max-bounded),
    and percentage tracks, gaps and margins;
  - named areas, auto-placement (sparse and `dense`), multi-size
    `grid-auto-rows/columns`;
  - the automatic minimum size of items;
  - abspos items in grid areas.
- **AppKit layer (libTrellis):**
  - TRBoxView, and the .trellis markup loader TRLoader (outlets by KVC,
    actions, templates, sample content);
  - view measurement, with the `TRSizeForWidth` hook for width-dependent
    views.
- **Tools:**
  - trellis-lint (markup, styles and owner bindings);
  - trellis-render (headless PNG and frame JSON with layout lint; window-free
    on macOS);
  - trellis-case (JSON conformance cases), trellis-bench, and the
    TrellisPreview app.
- **Builds:** GNUstep (gnustep-make; `make -j`, `make shared=no`,
  `make check`, `make check-gui`) and macOS (Makefile.macos, plain Apple
  clang).
- **Conformance at release, the same on Linux and macOS:**
  - Yoga gentest 906/906, WPT css-grid 1201/1201, and WPT css-flexbox
    827/838.
  - The 11 flexbox failures are the documented block-as-column divergence.
- **Known gaps:** no block or inline flow, no `calc()`, no named grid lines
  or subgrid, and abspos is relative to the parent box. See
  docs/known-issues.md.
