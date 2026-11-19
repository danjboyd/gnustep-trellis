# Design: subgrid (proposal)

Status: proposal, 2026-11-19. Nothing here is implemented. It's written
so the lead can decide whether subgrid goes into 0.12, and so whoever
builds it starts from the engine as it is now.

## Why

`grid-template-columns: subgrid` (or rows) lets a grid item that is
itself a grid use its parent's tracks instead of its own. The case
Trellis screens hit is **alignment across siblings**: a list of cards
whose title, body and button rows line up from card to card, or a form
whose label column has the same width in every fieldset. Today the only
way is to fix the track sizes by hand in each child grid, which breaks
as soon as one label is longer than the guess.

## How much it buys in conformance

At WPT 34bdce1, `css/css-grid/subgrid` has 196 files. Only 18 use
check-layout (the rest are reftests, which the importer can't
translate). They give **23 cases**, all tagged `subgrid` and skipped.
Run anyway, all 23 fail with "invalid value subgrid", so the count
covers the feature itself and nothing else. That's small next to grid
named lines (191 cases). The case for subgrid is app layout, not the
score.

## What the spec asks (CSS Grid 2, section 9)

For a grid item whose `grid-template-columns` (and/or `-rows`) is
`subgrid [<line-names>]*`:

1. **Its tracks are the parent's.** In the subgridded axis it has no
   explicit or implicit tracks of its own. Its span in the parent sets
   how many tracks it has, and its own placement is clamped to that span.
2. **Its items take part in the parent's track sizing**, as if they were
   placed in the parent, at the parent tracks under their subgrid
   position. The subgrid's own margin, border and padding count as an
   extra contribution on the first and last track it spans: half on each
   side when they're in the same track, otherwise all of it at that edge.
3. **Gaps:** the subgrid's own `column-gap` or `row-gap` replaces the
   parent's inside its span, as a correction to the items'
   contributions. `normal` inherits the parent's gap.
4. **Line names:** the parent's names come through, and
   `subgrid [a] [b]` adds names to the subgrid's lines.
5. **No implicit tracks** in that axis. An item placed past the span is
   clamped to the last line.
6. **Alignment:** `justify-content` and `align-content` do nothing in a
   subgridded axis. Items still self-align in their areas.
7. A subgrid that is also a grid in the other axis sizes that axis
   normally. Nested subgrids chain: tracks pass down through each level.

## Where it goes in the engine

All of it is in `Source/Engine/TRGrid.m`, `TRLayoutGrid`:

- **Parsing:** `TRParseTrackList` accepts `subgrid` followed by an
  optional `[names]` list (only for `grid-template-*`, never for
  `grid-auto-*`). The style keeps a per-axis flag, as it already does
  for the auto-flow keywords.
- **Placement** (the `TRPlace` loop): no change for the parent. A
  subgrid item is placed like any other, and its span is final.
- **Contributions** (`TRSizeTracks`, steps 1–2 of 12.5): before the
  parent sizes an axis, collect the descendant items of each subgrid
  item, recursively. Give each one a virtual placement in parent track
  indices (subgrid start + its own line, clamped). Add the subgrid's
  margin, border and padding to the edge items' contributions, and
  correct for the gap difference. That means `TRGridItem` gains a
  "virtual" kind that sizes but isn't laid out by the parent.
- **Layout of the subgrid:** when the parent lays out a subgrid item, it
  passes down its track positions and sizes for the span, rebased to the
  subgrid's content box: `TRLayoutGrid` gets an optional "inherited
  tracks" argument per axis. With that set, the subgrid skips
  `TRBuildTracks` and `TRSizeTracks` for the axis and places its items
  against the given tracks.
- **Measuring:** a subgrid measured on its own, outside a parent's
  layout pass (an intrinsic size query), falls back to sizing as a plain
  grid with `auto` tracks. Browsers do the same for a subgrid whose
  parent isn't a grid.

**The hard part is order.** The parent's row sizing needs the subgrid
items' heights at the parent's column widths. In a subgrid that is
subgridded in only one axis, those heights depend on the subgrid's own
tracks in the other axis. The engine's current two-pass flow (columns,
then row contributions at the resolved widths) holds, as long as the
subgrid's own-axis sizing can run first in that pass.

## Tests

- The 23 WPT cases, untagged, as the acceptance bar.
- Engine cases in `Tests/Engine/cases/grid.json`:
  - cards whose rows line up across siblings, through a one-axis
    subgrid;
  - margin, border and padding contributions at the edges;
  - a gap override;
  - names through `subgrid [a]`;
  - clamping past the span;
  - two levels of nesting.
- A markup case and a demo screen (a card wall with aligned buttons),
  checked with trellis-lint and a check-gui snapshot.

## Effort and risk

This is larger than named lines. Most of the work is the contribution
plumbing (the virtual items), plus the extra argument through
`TRLayoutGrid`. My estimate is one to two focused days, including the
nested and two-axis cases. The risk is regressions in track sizing for
ordinary grids. The current 1,800+ wpt-grid cases and the reference
dumps guard that well.

**Recommendation:** leave it out of 0.11. Build it as a single draft for
0.12, starting with one-axis subgrid (the card and form cases), then
both axes and nesting.
