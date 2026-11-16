# Trellis layout test-case format

One JSON file per case, under `Tests/Conformance/cases/<suite>/...json` (imported
suites) or `Tests/Engine/cases/*.json` (hand-written engine tests). The same
runner (`trellis-case`) reads both.

```json
{
  "id": "yoga/flex_direction/flex_direction_row",
  "source": {"suite": "yoga", "file": "YGFlexDirectionTest.html", "license": "MIT"},
  "available": {"width": null, "height": null},
  "direction": "ltr",
  "tolerance": 0.5,
  "requires": [],
  "root": {
    "style": {"width": 100, "height": 100, "flexDirection": "row"},
    "children": [
      {"style": {"width": 10}},
      {"style": {"width": 10}, "measure": {"width": 30, "height": 12}}
    ]
  },
  "expected": {
    "x": 0, "y": 0, "width": 100, "height": 100,
    "children": [
      {"x": 0,  "y": 0, "width": 10, "height": 100},
      {"x": 10, "y": 0, "width": 10, "height": 100}
    ]
  }
}
```

## Fields

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Unique, path-like. |
| `source` | imported cases | Suite, upstream file, licence. Keep upstream attribution. |
| `root` | yes | The node tree. Each node has `style` (object), optional `children` (array), optional `measure`. |
| `expected` | yes | The same tree shape, with `x`, `y`, `width`, `height` per node. Frames are the node's border box, relative to the parent's border box (like Yoga). A node may add `relativeTo: k` to make its `x`/`y` relative to the border box of the ancestor `k` levels up (1 is the parent). |
| `available` | no | The space the root is laid out into. A given width or height lays the root out *exactly* at that size, unless the root's own style sets the size. `null` or absent means unconstrained (the root takes its content size). |
| `direction` | no | `ltr` (default) or `rtl` for the root. |
| `tolerance` | no | Maximum absolute difference per number, default 0.5. |
| `pixelScale` | no | Pixel-grid rounding. Default 1 (Yoga-style rounding to whole points). 0 disables rounding (use this for WPT cases compared at sub-pixel precision). |
| `requires` | no | Features the case depends on, for example `["position-static","block-layout"]`. `trellis-case` skips a case that requires a feature Trellis doesn't implement, or does differently on purpose: `position-static`, `display-inline`, `display-inline-block`, `display-contents`, `display--webkit-box`, `logical-properties`, `intrinsic-size-keyword`, `overflow-axis` (overflow-x differs from overflow-y), `flex-wrap-balance`, `grid-named-lines`, `subgrid`, `grid-lanes` (masonry), `display-inline-grid`, `position-sticky` and `grid-template-shorthand` (`grid`/`grid-template` with area strings). It counts the skips by feature. `--all` runs every case, and `--unsupported a,b` replaces the list. |
| `anchor` | no | Child-index path to a node (`[]` is the root, `[0, 2]` the root's first child's third child). Expected nodes may then carry `dx`/`dy`: their border-box offset from the anchor's border box. The WPT importer uses this for offsets whose offsetParent is `<body>`, where only differences between elements are known. |
| `skip` | no | A string: the reason this case is known bad and skipped. |

## Styles

- Keys are CSS property names in camelCase (`flexDirection`) or kebab-case
  (`flex-direction`). The engine canonicalises both.
- Numbers are px. Strings are CSS values: `"50%"`, `"auto"`, `"10px 20px"`,
  `"1 1 0"`. Shorthands (`flex`, `margin`, `padding`, `inset`, `gap`,
  `border-width`, `flex-flow`, `place-*`) are accepted.
- CSS initial values apply, with two deliberate departures:
  `box-sizing` defaults to **border-box**, and `display` defaults to
  `flex` (`display: block` means a column flex container). Otherwise
  `flex-direction:row`, `flex-shrink:1`, `min-width/height:auto`.
  **WPT imports must set `"boxSizing": "content-box"` on every node.**
  Yoga imports need nothing (Yoga is border-box too).
- **Grid** properties (`display: "grid"`, `gridTemplateColumns`,
  `gridTemplateAreas`, `gridColumn`, …) use the same CSS value syntax.
  Named lines and subgrid are not supported: mark such cases with
  `"requires": ["grid-named-lines"]` or `["subgrid"]`.
- **Positioning:** an absolutely positioned child is placed against its
  parent's padding box (Yoga semantics), whatever the parent's `position`.
  WPT imports should give the container `position:relative`, which makes
  this match the browser.

## `conditions` (container queries)

Any node may carry
`"conditions": [{"when": "width < 300px", "style": "flex-direction: column"}]`.
Each condition is tested against the inner width of the nearest ancestor
with `containerType: "inline-size"` (or the root), and the style is applied
on top when it matches. See `TRNode -addConditionalStyle:when:error:`.

## `measure` (leaves only)

- `{"width": W, "height": H}` is a fixed intrinsic content size (excluding
  padding and border), like a Yoga measure function that returns a constant.
- `{"text": "aa aaa", "charWidth": 10, "lineHeight": 10}` is an Ahem-style
  text measurer: every character is `charWidth` wide, text wraps at spaces,
  each line is `lineHeight` tall. Its min-content width is the longest word;
  its max-content width is the whole string. Use it for WPT Ahem cases and
  Yoga measure-function cases.
  A `"\n"` in the text is a forced line break (an imported `<br>`): each
  line wraps on its own, and max-content is the longest line.
  `"nowrap": true` (from `white-space: nowrap`/`pre`) disables wrapping.
- `"baseline": N` (optional, with either form) gives the leaf's first
  baseline, measured from its top border edge. Without it, the baseline is
  the bottom of the border box.

## Runner output

`trellis-case [--verbose] [--all | --unsupported a,b] <dir-or-file>...` prints one line per failure and then:

```
PASS 812/1000 (81.2%)  fail 150  skip 38
  yoga: 400/420 (95.2%)
  wpt:  412/580 (71.0%)
```

It exits non-zero if any non-skipped case fails.

`make check` runs the conformance cases as a report that never fails the
build. It prints each failing case id, then the totals, the per-suite rates
and the skip reasons.

## Current results

The README's Conformance table is generated from recorded runs on Linux and
macOS (`docs/conformance/*.json`, written by `make conformance-record`), so
it's the one source of truth for pass rates. All 11 flexbox failures
(`percentage-heights-001`, `percentage-size/2`) come from `display: block`
being a column; see docs/agents.md section 4.
