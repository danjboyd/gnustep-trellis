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
  `separator`, `spacer`, and `view type="MyNSViewSubclass"`.
- **Text:** put a label's or button's text in its content:
  `<button>Save</button>`.
- **Outlets:** `id="search"` sets the owner's `search` property. Every id
  must have a matching property, unless you write `no-outlet="yes"`.
- **Actions:** `action="compose:"` sends `compose:` to the owner, which
  must implement it.
- **Keyboard focus:** Tab follows document order, as in a browser:
  Trellis links the controls into the window's key-view loop after every
  layout, so controls hidden by `display: none` (or a container query)
  drop out and come back by themselves. CSS `order` doesn't change it.
  `tabindex="1"`, `"2"`, ... go first, in that order; `tabindex="-1"`
  leaves a control out. Scrolled content joins the loop. For the first
  responder, use the root box's `firstKeyView`.
- **Accessibility:** every control needs a name a screen reader can read.
  Name a control with a visible label, `<label label-for="theme">Theme</label>`,
  or with `a11y-label="Snooze"` when there's no visible text (a popup that
  shows its value, an icon button, a text view). `role="group"` names a
  container (with `a11y-label`); `role="none"` hides a decorative image.
  trellis-lint warns `unlabeled` for fields (a placeholder counts),
  popups, sliders, progress bars, images and custom views without a name,
  and for buttons and checkboxes without a title. On Cocoa these reach
  NSAccessibility; on GNUstep they're recorded but not yet exposed (see
  known-issues.md).
- **Sample content:** put it in `Screen.sample.json`, keyed by id. It's
  used only by trellis-render.

## 3. CSS that works

- **Properties:** `display` (`flex`, `none`, `block`), `flex-direction`,
  `flex-wrap`, `flex-flow`, `flex`, `flex-grow`, `flex-shrink`,
  `flex-basis`, `justify-content`, `align-items`, `align-self`,
  `align-content` (`justify-*` also take physical `left`/`right`; `justify-content` and `align-content` take a `safe`/`unsafe` prefix), `place-*`, `gap`, `row-gap`, `column-gap`, `order`,
  `width`, `height`, `min-*`, `max-*`, `aspect-ratio`, `margin` (with
  `auto`), `padding`, `border` (width only for layout), `position`
  (`relative`, `absolute`), `top`, `right`, `bottom`, `left`, `inset`,
  `overflow`, `box-sizing`, `direction`.
- **Grid** (`display: grid`): `grid-template-columns` and
  `grid-template-rows` take `px`, `%`, `fr`, `auto`, `min-content`,
  `max-content`, `minmax()` and `repeat(N | auto-fill | auto-fit, …)`.
  Also `grid-template-areas`, `grid-auto-rows` and `grid-auto-columns` (one or more sizes),
  `grid-auto-flow: row | column`, `grid-row`, `grid-column` (`2 / 4`,
  `span 2`, `1 / -1`), `grid-area` (an area name or four lines),
  `justify-items`, `justify-self`, `align-items`, `align-self`,
  `justify-content` and `align-content`.
  `fit-content(N)` (px or %) caps a track at N.
  `grid-auto-flow` takes `dense`.
  **Not supported:** named lines (`[name]`) and `subgrid`.
- **Drawing:** `background-color` and `border-color`/`border-radius` on
  boxes; `color`, `font-size`, `font-weight` and `text-align` on text
  controls; `white-space: nowrap`.
- **Colours: use system colours,** so the UI follows Light/Dark on macOS
  and the GNUstep theme (Adwaita light or dark, Gumdrop). Use `Canvas` with
  `CanvasText` for a content background and its text,
  `-tr-window-background` for panels, `GrayText` for secondary text,
  `AccentColor` for accented backgrounds (`LinkText` for coloured text: Cocoa's
  accent colour doesn't adapt to Dark), `Highlight` with `HighlightText` for selections,
  `ButtonFace`/`ButtonText`, `Field`/`FieldText`, `LinkText`,
  `-tr-separator` for borders and `-tr-error` for errors.
  - A fixed colour (`#fff`) next to a system one breaks in the other
    appearance: white text on white.
  - trellis-lint warns (`colour-pair`) about a fixed background with text
    that follows the system, or the reverse.
  - `trellis-render --appearance dark --lint` reports `low-contrast` text
    from the resolved colours.
- **Units:** `px`, `%` and `auto`.
- **Selectors:** `type`, `.class`, `#id`, `a b`, `a > b`, and comma
  lists. **Not supported:** `:hover` and other pseudo-classes, attribute
  selectors, `+`, `~`, and `!important` ordering.
- **Container queries:**
  `@container (min-width: 560px) { ... }` and `(max-width: ...)`. The
  condition tests the nearest ancestor with
  `container-type: inline-size`. Put that on your root.
- **Unknown properties and bad values are errors,** with `file:line:col`.

## 4. Where Trellis is not the browser

| Topic | Browser CSS | Trellis |
|---|---|---|
| Every element | block or inline | a **flex container** (default `flex-direction: row`) |
| `<row>` | n/a | `flex-direction: row; align-items: center` |
| `<column>` | n/a | `flex-direction: column` (items stretch to full width) |
| `display: block` | block flow | a column |
| `box-sizing` | `content-box` | **`border-box`**: `width` includes padding and border |
| `position: absolute` | relative to the nearest positioned ancestor | relative to the **parent** |
| `last baseline` | aligns last baselines | aligns as `end` (its fallback) |
| No block or inline flow, floats or tables | | use rows and columns |

**`display: block` is a column, and that has three visible effects.**
Trellis keeps this on purpose: one layout model (flex) is predictable,
fast, and what responsive app UI wants. Browser block flow exists for
documents. The effects:

1. **Children shrink instead of overflowing.** Items default to
   `flex-shrink: 1`, so a `height: 100px` child in a 50px-tall block is
   squeezed down to its content. In a browser it would overflow. Set
   `flex-shrink: 0` on children that must keep their size.
2. **Percentage heights resolve.** A child of a definite-height block has a
   definite height after flexing, so `height: 50%` on a grandchild works.
   In a browser, an auto-height block makes it `auto`.
3. **Margins never collapse**, between siblings or through a parent.

The WPT importer tags cases that rely on block flow `requires: block-layout`.
The runner still runs them: most pass, because a column usually lays
out a block the same way. The divergence itself shows in
`percentage-heights-001` (effect 1) and `percentage-size` (effect 2).

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

A custom view whose height depends on its width (a text view at natural
height, say) can implement `-trellisSizeForWidth:` (the `TRSizeForWidth`
protocol in TRViewMeasure.h). Trellis calls it with the width on offer,
or `CGFLOAT_MAX` for the view's max-content size, and lays it out in one
pass. Outlets bind by KVC, so an `IBOutlet` ivar `_title` serves
`id="title"`, and lint accepts it.
