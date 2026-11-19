# Writing Trellis UI: a guide for coding agents

Trellis lays out GNUstep and Cocoa views with CSS Flexbox and Grid. If you
know CSS, you already know most of Trellis. This page covers what is
different, the files you write, and the loop you use to check your work.
The supported API, which stays stable within a version, is listed in
[api.md](api.md).

## 1. The loop

Always render and lint what you write. Don't trust your mental model of the
layout. Check `--appearance dark` as well as light.

```sh
. scripts/env.sh
scripts/run-headless.sh obj/trellis-render Screen.trellis --widths 340,520,800 \
    --theme Adwaita --png /tmp/screen.png --json /tmp/screen.json --lint
obj/trellis-lint Screen.trellis --owner ScreenController.h
```

1. **Look at the PNGs.** There's one per width (`/tmp/screen-340.png` and so
   on). Add `--outlines` to see box edges.
2. **Read `/tmp/screen-<w>.json`.** It holds every view's frame,
   intrinsic size, text and matched container conditions.
3. **Fix every lint error.** Rules:
   - `clipped-text`: the text doesn't fit; give it room or let it wrap.
   - `undersized`: a control is smaller than its intrinsic size.
   - `stretched`: a fixed-height control was stretched; see §4.
   - `overlap`: siblings overlap.
   - `overflow`: a child sticks out of its box.
   - `offscreen`: a view is outside the viewport.
   - `outlet` / `action`: an id or action= doesn't match the owner class.
   - `unitless`: a length has no `px`.
4. **Check at least three widths:** narrow (about 340), medium (about 520)
   and wide (800 or more).

Never run GUI programs outside `scripts/run-headless.sh`. It gives each
run a private display and a throwaway `GNUSTEP_HOME`, so you can't damage
the user's settings. trellis-render refuses to run without it.

## 2. A .trellis file

```html
<!-- owner: InboxController -->
<column id="inbox" class="page">
  <row class="toolbar">
    <field id="search" placeholder="Search"/>
    <button action="compose:">New</button>
  </row>
  <scroll>
    <label id="empty" class="muted">No messages</label>
  </scroll>
</column>

<style>
  .page    { container-type: inline-size; padding: 12px; gap: 8px; }
  .toolbar { gap: 8px; }
  #search  { flex: 1; min-width: 120px; }
  .muted   { color: #77767b; }
  @container (max-width: 400px) { .toolbar { flex-wrap: wrap; } }
</style>
```

- **Structure:** one root element (`column`, `row` or `box`) and one
  `<style>` block. Add `<!-- owner: ClassName -->` so lint knows the owner
  class.
- **Elements:** `column`, `row`, `box`, `scroll`, `label`, `text` (a
  wrapping label), `field`, `button`, `checkbox`, `radio`, `popup` (with
  `<item>` children or `items="A, B"`), `image`, `slider`, `progress`,
  `separator`, `spacer`, `segmented` (since 0.5), `split` (resizable
  panes, since 0.5), `virtual`,
  and `view type="MyNSViewSubclass"`.
- **Text:** put a label's or button's text in its content:
  `<button>Save</button>`.
- **Outlets:** `id="search"` sets the owner's `search` property. Every id
  must have a matching property, unless you write `no-outlet="yes"`.
- **Actions:** `action="compose:"` sends `compose:` to the owner, which
  must implement it.
- **Flat buttons:** `<button bordered="no">` draws the title only (chips
  on a coloured bar); `color:` colours a button's title. Setting the
  title later in code drops the colour: set `attributedTitle` instead.
- **Segmented controls (since 0.5):** `<segmented action="viewChanged:"
  selected="Tiles"><item>Tiles</item><item>Table</item></segmented>` (or
  `items="Tiles, Table"`). `tracking="one"` (default: a switch),
  `"any"` (toggles; mark several with `<item selected="yes">`) or
  `"momentary"` (buttons, which hold no selection, so `selected` is an
  error there). Segments share the width equally and the
  control asks for room for its longest label. In code it's a
  `TRSegmentedControl`: `selectedTitles` reads and sets the selection; in
  a sample file, `{"selected": "Table"}` or a list of titles.
- **Hiding (since 0.5):** `hidden` (or `hidden="yes"`) starts an element
  hidden; in code, `[box setHidden: NO forSubview: view]` shows it again.
  A hidden view is laid out as if `display: none`, but its style is left
  alone, so showing it restores the style's own `display` (no need to
  write `display: flex` back). A plain `-setHidden:` on the view doesn't
  last: the next layout shows or hides views by their style and this
  flag. In a sample file, `"hidden": true` does the same.
- **Disabling (since 0.5.1):** `disabled` on a control greys it out; on a
  container (a row, a column, a split) it disables every control inside,
  like an HTML fieldset, and leaves labels as they are. In code,
  `TRSetEnabled(view, YES)` turns a control or a container back on (a
  plain `-setEnabled:` works for one control). Disabled controls stay in
  the Tab order and Tab skips them, so enabling one needs no relayout. A
  virtual box's items aren't reached: set them up from the data source.
  In a sample file, `"disabled": true` does the same. Lint warns on
  `disabled` on a label, text, image, spacer, separator or progress bar.
- **Right-to-left (since 0.6):** `dir="rtl"` on an element (as in HTML)
  sets `direction: rtl` for it and its content; style rules and inline
  styles can still override it. Rows run right to left, and logical sides
  (`margin-inline-start` ...) swap. Split panes and scroll views keep the
  direction of the element around them. `dir` takes `ltr` or `rtl`; any
  other value is an error. On Cocoa, an app running in a right-to-left
  localization lays out rtl by default. Tab order stays document order,
  which is reading order in either direction. Split panes are not
  reordered: the first pane stays on the left.
- **Keyboard focus:** Tab follows document order, as in a browser:
  Trellis links the controls into the window's key-view loop after every
  layout, so controls hidden by `display: none`, a container query or
  `hidden` drop out and come back by themselves; if the focused control
  is hidden, focus moves to the next one. CSS `order` doesn't change it.
  `tabindex="1"`, `"2"`, ... go first, in that order; `tabindex="-1"`
  leaves a control out. Don't put a positive one in a `<template>`
  (lint warns): every copy shares it. Scrolled content joins the loop. For the first
  responder, use the root box's `firstKeyView`. The loop wraps through
  the root box, so a screen whose controls are all hidden or disabled
  never stalls Tab.
- **Accessibility:** every control needs a name a screen reader can read.
  Name a control with a visible label, `<label label-for="theme">Theme</label>`,
  or with `a11y-label="Snooze"` when there's no visible text (a popup that
  shows its value, an icon button, a text view). `role="group"` names a
  container (with `a11y-label`); `role="none"` hides a decorative image.
  trellis-lint warns `unlabeled` for fields (a placeholder counts),
  popups, segmented controls, sliders, progress bars, images and custom
  views without a name, for buttons and checkboxes without a title, and
  for a segmented item with no text. A segmented control's name is the
  group's (`a11y-label="View"`); its items name themselves. It also warns
  when a `label-for` target is hidden but its label isn't: hide them
  together by hiding a box that holds both. On Cocoa these reach
  NSAccessibility; on GNUstep they're recorded but not yet exposed (see
  known-issues.md).
- **Sample content:** put it in `Screen.sample.json`, keyed by id. It's
  used only by trellis-render.

**Rich text in labels.** A `<label>` or `<text>` may contain `<b>` (or
`<strong>`), `<i>` (or `<em>`), `<code>`, `<br/>` and links. Whitespace
collapses as in HTML, and the runs follow the label's `color`,
`font-size` and `text-align`.

```xml
<text class="note">Ticket <a action="openTicket:" href="482">#482</a> is <b>blocked</b>;
  run <code>make check</code>.<br/>See <a href="https://example.com/guide">the guide</a>.</text>
```

- `<a action="openTicket:" href="482">` sends `openTicket:` to the owner
  with the label as sender; `[(TRRichLabel *)sender clickedLink]` is the
  href. trellis-lint checks the action like any other.
- `<a href="https://...">` with no action opens the URL (http, https and
  mailto only).
- Links draw in `LinkText`, underlined. On GNUstep the underline and the
  slant of `<i>` (when the font has no italic face) may not draw.
- Links are clicked, not tabbed to: put anything the keyboard must reach
  in a button.

## 3. CSS that works

- **Properties:** `display` (`flex`, `none`, `block`), `flex-direction`,
  `flex-wrap`, `flex-flow`, `flex`, `flex-grow`, `flex-shrink`,
  `flex-basis`, `justify-content`, `align-items`, `align-self`,
  `align-content` (`justify-*` also take physical `left`/`right`; `justify-content` and `align-content` take a `safe`/`unsafe` prefix; on `align-items`/`align-self` a flex container accepts it and ignores it), `place-*`, `gap`, `row-gap`, `column-gap`, `order`,
  `width`, `height`, `min-*`, `max-*`, `aspect-ratio`, `margin` (with
  `auto`), `padding`, `border` (width only for layout), `position`
  (`relative`, `absolute`, `static`), `top`, `right`, `bottom`, `left`, `inset`,
  `overflow`, `box-sizing`, `direction`.
- **Logical properties** follow each box's `direction` (horizontal writing
  only): `margin-inline-start`/`-end`, `padding-inline-*`,
  `border-inline-*`, `inset-inline-*`, the `-block-*` forms (top and
  bottom), the shorthands `margin-inline`, `padding-inline`,
  `inset-inline` (and `-block`), and `inline-size`/`block-size` with
  `min-`/`max-`. Prefer them for start/end spacing so rtl works.
- **Grid** (`display: grid`): `grid-template-columns` and
  `grid-template-rows` take `px`, `%`, `fr`, `auto`, `min-content`,
  `max-content`, `minmax()` and `repeat(N | auto-fill | auto-fit, …)`.
  Also `grid-template-areas`, `grid-auto-rows` and `grid-auto-columns` (one or more sizes),
  `grid-auto-flow: row | column`, `grid-row`, `grid-column` (`2 / 4`,
  `span 2`, `1 / -1`), `grid-area` (an area name or four lines),
  `justify-items`, `justify-self`, `align-items`, `align-self` (each
  with an optional `safe`/`unsafe` prefix: `safe` puts an item that
  overflows its area at the area's start; unsafe is the default),
  `justify-content` and `align-content`.
  `fit-content(N)` (px or %) caps a track at N.
  `grid-auto-flow` takes `dense`.
  **Not supported:** named lines (`[name]`) and `subgrid`.
- **Drawing:** `background-color` and `border-color`/`border-radius` on
  boxes; `border-style` (or the style in `border:`) `solid`, `dashed`,
  `dotted` or `double` (since 0.5; `groove`, `ridge`, `inset` and `outset`
  draw solid, and `none` or `hidden` in `border:` means no border);
  per-side borders `border-top`/`-right`/`-bottom`/`-left: 1px solid
  -tr-separator` and their `-color`/`-style` longhands (since 0.5; sides
  that differ draw square corners); `color`, `font-size`, `font-weight` and `text-align` on text
  controls; `white-space: nowrap`.
- **Layout transitions (opt-in):** `-tr-layout-transition: 200ms` on a box
  (optionally `linear` or `ease-in-out`; the default is ease-out) makes its
  subviews, and nested boxes' unless they say `none`, glide to their new
  frames when the layout changes because content or style changed: a
  panel shown or hidden, an expander opened, a class swapped. Window
  resizes never animate, and nothing animates when the user asks for
  reduced motion. Use it on the root of a screen with expanders or
  dismissable banners; keep it at 150-250 ms.
- **Colours: use system colours,** so the UI follows Light/Dark on macOS
  and the GNUstep theme (Adwaita light or dark, Gumdrop). Use `Canvas` with
  `CanvasText` for a content background and its text,
  `-tr-window-background` for panels, `GrayText` for secondary text,
  `AccentColor` for accented backgrounds (`LinkText` for coloured text: Cocoa's
  accent colour doesn't adapt to Dark; on GNUstep both take the theme's
  selection blue, or a fixed blue when the theme's is grey, as in the
  default theme), `Highlight` with `HighlightText` for selections,
  `ButtonFace`/`ButtonText`, `Field`/`FieldText`, `LinkText`,
  `-tr-separator` for borders and `-tr-error` for errors.
  `Mark` with `MarkText` and `-tr-warning-background` with
  `-tr-warning-text` (a soft peach with dark brown) are highlights that
  stay light in both appearances: always pair them with their own text
  colour.
  - A fixed colour (`#fff`) next to a system one breaks in the other
    appearance: white text on white.
  - trellis-lint warns (`colour-pair`) about a fixed background with text
    that follows the system, or the reverse.
  - `trellis-render --appearance dark --lint` reports `low-contrast` text
    from the resolved colours.
- **Target size:** `trellis-render --lint` (and Preview's inspector) warn
  with `touch-target` when a control is under 24x24 px and its 24 px
  circle reaches another control (WCAG 2.2, 2.5.8). Desktop controls about
  22 px tall pass with a normal gap; tight rows of small icon buttons
  don't. Give them `min-width`/`min-height: 24px` or a `gap`.
- **Units:** `px`, `%` and `auto`. `width`, `height`, their `min-`/`max-`
  forms and `flex-basis` also take `min-content`, `max-content`,
  `fit-content` and `stretch` (since 0.8; `flex-basis: stretch` acts as
  `content`, as in Yoga), and `initial` (their initial value: `auto`, or
  `none` for `max-*`).
- **Selectors:** `type`, `.class`, `#id`, `a b`, `a > b`, and comma
  lists. **Not supported:** `:hover` and other pseudo-classes, attribute
  selectors, `+`, `~`, and `!important` ordering.
- **Container queries:**
  `@container (min-width: 560px) { ... }` and `(max-width: ...)`. The
  condition tests the nearest ancestor with
  `container-type: inline-size`. Put that on your root.
- **Custom properties and tokens:** declare `--name: value` on an element
  (usually the root) and use `var(--name)` or `var(--name, fallback)` in
  any value. They inherit down the tree, and a descendant can redefine
  them. Built-in tokens are defined everywhere, and the metric ones come
  from the running theme, so prefer them to hard-coded numbers:
  - fonts: `--tr-font-size`, `--tr-small-font-size`,
    `--tr-label-font-size`, `--tr-title-font-size`;
  - controls: `--tr-control-height`, `--tr-field-height`,
    `--tr-scroller-width`;
  - spacing and corners: `--tr-space-xs` (2px), `-s` (4), `-m` (8),
    `-l` (12), `-xl` (20); `--tr-radius-s` (4), `--tr-radius` (6),
    `--tr-radius-l` (10);
  - colours (aliases of the system colours above): `--tr-text`,
    `--tr-surface`, `--tr-window`, `--tr-muted`, `--tr-border`,
    `--tr-accent`, `--tr-accent-text`, `--tr-link`, `--tr-danger`,
    `--tr-warning` / `--tr-warning-text`, `--tr-highlight` /
    `--tr-highlight-text`.

  ```css
  .app  { --gap: var(--tr-space-m); gap: var(--gap); padding: var(--tr-space-l); }
  .card { --gap: var(--tr-space-s); gap: var(--gap); border-radius: var(--tr-radius); }
  @container (max-width: 399px) { .app { --gap: var(--tr-space-s); gap: var(--gap); } }
  ```

  An undefined `var()` without a fallback is an error at the element. A
  custom property set inside `@container` applies only inside that block
  (write the `var()` uses there too, as above). No `calc()` yet.
- **Unknown properties and bad values are errors,** with `file:line:col`.

## 4. Where Trellis is not the browser

| Topic | Browser CSS | Trellis |
|---|---|---|
| Every element | block or inline | a **flex container** (default `flex-direction: row`) |
| `<row>` | n/a | `flex-direction: row; align-items: center` |
| `<column>` | n/a | `flex-direction: column` (items stretch to full width) |
| `display: block` | block flow | a column whose children don't flex (since 0.6) |
| `box-sizing` | `content-box` | **`border-box`**: `width` includes padding and border |
| `position: absolute` | relative to the nearest positioned ancestor | the same, but boxes default to `position: relative`, so that's the **parent** unless it is `position: static` |
| `last baseline` | aligns last baselines | aligns as `end` (its fallback) |
| No block or inline flow, floats or tables | | use rows and columns |

**`display: block` is a column whose children don't flex.** Trellis has
no block flow: a block stacks its children top to bottom and stretches
them across, like a column, so the whole engine stays one layout model.
Since 0.6 it matches the browser where a column used to differ:

1. **Children keep their size.** They never grow or shrink, and
   `flex`, `flex-grow`, `flex-shrink` and `flex-basis` on them do nothing
   (trellis-lint warns). A `height: 100px` child in a 50px-tall block
   overflows, as in a browser. Use a `<column>` when children should flex.
2. **Percentage heights follow CSS.** A child's `height: 50%` resolves
   only against a definite height: a fixed height, a stretched flex item,
   or a flexed item of a column with a definite height (css-flexbox 9.8).
   Against an auto height it acts as `auto`. This holds for every box,
   not only blocks.
3. **Margins never collapse**, between siblings or through a parent. This
   is still a difference from the browser.

The WPT importer tags cases that rely on block flow `requires: block-layout`.
The runner still runs them, and all of them pass.

**The most common mistake:** `flex-basis` (and the third value of
`flex`) applies to the *main* axis. `flex: 1 1 160px` means 160px wide in
a row but **160px tall in a column**. If a container switches direction
in a container query, set `flex-basis` only inside the query that makes
it a row. Lint reports this as `stretched`.

## 5. Patterns

- **Label column in a form:** each field is a `row` with a
  `flex: 0 0 120px; text-align: right` label and a `flex: 1` control. At
  narrow widths, switch the row to `flex-direction: column` with a
  container query.
- **Push items apart:** `<spacer/>` (which is `flex: 1`), or
  `margin-left: auto` on the item to push right.
- **Equal buttons that wrap:** `#options { flex-wrap: wrap; gap: 6px }` and
  `#options > button { flex: 1 1 160px }` (in a row).
- **Truncating vs wrapping:** labels don't wrap by default. Use `<text>` or
  `wraps="yes"` for paragraphs.
- **Page layout:** use a grid with `grid-template-areas` on the root,
  and swap the areas in a container query for narrow widths (see
  `Examples/TrellisDemo/Dashboard.trellis`).
- **Responsive cards:**
  `grid-template-columns: repeat(auto-fill, minmax(150px, 1fr))`. The
  number of columns follows the width, and you don't need a query.
- **Hide on narrow screens:** `@container (max-width: 499px) { #share { display: none } }`.
- **Scrolling content:** wrap it in `<scroll>`. The scroll view takes the
  remaining space (`flex: 1`), and its content is a column.
- **Long lists and walls (hundreds of items or more): `<virtual>`.** Only
  the items on screen get views, so 10,000 rows cost what 30 do. Each
  item is a copy of a `<template>`; the owner's code (or a sample file)
  supplies the data. Ids may repeat across templates.

  ```xml
  <virtual id="wall" layout="grid" template="tile" estimated-size="110">
    <template id="tile"><column class="tile"><label id="name"/><text id="status"/></column></template>
    <template id="group"><label id="title" class="group"/></template>
  </virtual>
  <style>
    #wall  { grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 10px; padding: 12px; }
    .group { grid-column: 1 / -1; font-weight: bold; }   /* a whole row: a header */
  </style>
  ```

  - `layout="list"` (default) is one item per row; `grid` uses the
    element's `grid-template-columns`. Margins on items are ignored; use
    `padding` inside the template.
  - Sample file: `{"wall": {"items": [{"_template": "group", "title":
    "Working (3)"}, {"_repeat": 3, "items": [{"name": "agent-{n:2}",
    "status": "Working"}]}]}}`. `trellis-render` then shows the wall
    filled, and lints the visible items.
  - In code, set `dataSource` (`TRVirtualDataSource`: count, configure a
    view for an index, optionally the template per index) and report
    changes with `-insertItemsAtIndexes:` and friends. A reused view still
    holds the previous item's content, so set every field.
  - Keyboard and accessibility come built in: Tab walks the items in
    order and scrolls past the edge; the box is a list or grid with the
    full count.
- **Resizable panes: `<split>`** (since 0.5). Each child is a pane, with a
  draggable divider between neighbours. Along the split, a pane's CSS
  `width` (or `height` in a column) is its starting size, `min-`/`max-`
  limit dragging, and `flex-grow` picks the panes that take the extra
  space when the window grows (the last pane when none says).
  `autosave="name"` keeps the divider positions in the user defaults
  across launches.

  ```xml
  <split autosave="main-window">
    <column class="sidebar">...</column>
    <split class="content" direction="column">
      <scroll class="list">...</scroll>
      <column class="detail">...</column>
    </split>
  </split>
  <style>
    .sidebar { width: 220px; min-width: 160px; max-width: 360px; }
    .content { flex-grow: 1; }
    .list    { height: 240px; min-height: 120px; }
  </style>
  ```

  - `direction="row"` (default: side by side) or `"column"` (stacked);
    `divider="thin"` (default), `"thick"` or `"pane"`.
  - The split fills the remaining space (`flex: 1`), like `<scroll>`.
  - In code: `-dividerPositions`, `-setDividerPositions:` (clamped to the
    limits, saved under `autosave`), and `target`/`action`, sent after
    the user drags a divider.
  - Keyboard: the split is a Tab stop after its first pane (on macOS
    only with full keyboard access, like buttons). Left/Right (Up/Down
    when stacked) move the divider 10pt, 1pt with Option; Home and End
    move it to its limits; `[` and `]` pick the divider when there are
    several. Keyboard moves are saved and send the action, like drags.
    `disabled` on a split stops dragging and the keyboard too.
  - A pane can be hidden: `hidden` on it in markup, or
    `[split setHidden: YES forPane: pane]` in code (`-isPaneHidden:`).
    The pane and its divider leave and the other panes take its space;
    shown again, it comes back in its place at the size it had. Focus in
    a pane being hidden moves to the next view. Use it for a sidebar or
    inspector the user toggles. (`-setHidden:forSubview:` is for box
    children; a pane belongs to the split.)
  - `display: none` in a pane's style hides it the same way (since 0.7.1),
    so a container query can drop a sidebar at narrow widths:
    `@container (max-width: 500px) { .side { display: none; } }`. It comes
    back when the query stops matching. A pane is out while either
    `hidden` or `display: none` holds; `-isPaneHidden:` reports either.

## 6. From code

```objc
TRBoxView *row = [TRBoxView boxWithStyle: @"flex-direction: row; gap: 8px; align-items: center"];
[row addSubview: titleField style: @"flex: 1"];
[row addSubview: okButton];                      // its intrinsic size
[row addConditionalStyle: @"flex-direction: column" when: @"width < 400px"];

NSError *err;
TRBoxView *screen = [TRLoader loadFile: @"Inbox.trellis" owner: self error: &err];
```

Call `-[TRBoxView invalidateSubview:]` after changing a view's content
outside Trellis, for example an image. Text and title changes on
NSControls are noticed automatically.

**Hot reload while you develop.** Run the app with `TRELLIS_HOT_RELOAD=1`
(or the `TRHotReload` default) and edit its .trellis files: every box
loaded with `+loadFile:owner:error:` is rebuilt within half a second of a
save. The new box takes the old one's place, outlets and actions are
bound again, and the owner gets `-trellisDidReload:`; refill content
there. A file that doesn't load is reported on stderr and the old layout
stays. It's off unless you turn it on, and release builds can compile it
out with `make hot_reload=no`. Boxes nested inside another Trellis box
aren't swapped.

A custom view whose height depends on its width (a text view at natural
height, say) can implement `-trellisSizeForWidth:` (the `TRSizeForWidth`
protocol in TRViewMeasure.h). Trellis calls it with the width on offer,
or `CGFLOAT_MAX` for the view's max-content size, and lays it out in one
pass. This is the way to put rendered Markdown, chat bubbles or any
custom-drawn text in a layout: return the height your drawing needs at
that width, and call `-[TRBoxView invalidateSubview:]` when the content
changes. Without it, a custom view is measured by its intrinsic content
size (or its frame). Outlets bind by KVC, so an `IBOutlet` ivar `_title` serves
`id="title"`, and lint accepts it.
