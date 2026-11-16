# Design: virtualized lists and grids

Status: implemented in 0.4 (2026-11-16): TRVirtualLayout, TRVirtualBox,
`<virtual>`, focus, accessibility, benchmarks and the Work-wall spec
(dogfood/work/Work-virtual.trellis). Differences from this proposal:

- **No item keys yet.** Sizes, focus and realized views follow indexes,
  shifted on insert and remove; `keyForItemAtIndex:` is not asked.
- **No `selected` class toggle.** The app draws selection (or uses a
  template for the selected state).
- **Only visible items join the key-view loop**, plus the focused item
  if it scrolled away; overscan items don't, so focus never lands off
  screen. The sentinels sit just outside the visible items.
- **Rows update in place on measure:** a measured height fixes its row
  and recomputes row tops lazily from there (no Fenwick tree needed so
  far: 0.25 ms per step at 100,000 items).
- **Measured** (Linux, `trellis-bench --virtual 10000`, and
  Tests/View/virtual-bench.m with real views in a 900x800 window): see
  CHANGELOG 0.4.0.

## Why

A Trellis screen builds one NSView per element and lays out the whole
tree. That is fine for a settings pane. A list of 10,000 tickets, a long
thread or a wall of a few hundred tiles needs something else: memory and
layout time that grow with what is on screen, not with the data.

The targets are the shapes a consumer app already has:

- **a list of rows:** an ask thread, a ticket list, a log;
- **a wall of tiles in auto-fill columns:** with group headers that span
  the whole row ("Needs you (1)", "Working (4)").

## What the app writes

```xml
<virtual id="tiles" template="tile" layout="grid"
         estimated-size="110" overscan="1">
  <template id="tile"> ... one tile ... </template>
  <template id="group"> <label class="group-title"/> </template>
</virtual>
<style>
  #tiles { grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));
           gap: 10px; padding: 12px; }
  .group-title { grid-column: 1 / -1; }
</style>
```

- `<virtual>` builds a **TRVirtualBox**, a scroll view (like `<scroll>`)
  whose content is laid out by the window engine below.
- `layout="list"` is the default: a column, with flex styles on the
  items. `layout="grid"` uses the element's grid styles.
- **Templates are the items.** Each item is a fresh copy of one of the
  element's `<template>`s, made with the existing
  `+instantiateTemplate:...` path, and then reused.
- The owner gets the box through the outlet (`id="tiles"`) and sets its
  data source.

The typed API is the same thing without markup:
`[[TRVirtualBox alloc] initWithLayout: TRVirtualLayoutGrid]`, plus
`-registerTemplate:ofDocument:` or `-registerViewFactory:forKind:`.

## Data source

```objc
@protocol TRVirtualDataSource <NSObject>
- (NSInteger)numberOfItemsInVirtualBox:(TRVirtualBox *)box;
/* Fill a view made from the item's template (fresh or reused). */
- (void)virtualBox:(TRVirtualBox *)box configureView:(NSView *)view
           atIndex:(NSInteger)index;
@optional
/* The template for an item (default: the element's template=). Group
   headers return @"group". Asked for every index, so it must be cheap. */
- (NSString *)virtualBox:(TRVirtualBox *)box templateForItemAtIndex:(NSInteger)index;
/* A stable identity, so sizes, focus and selection follow an item when
   others are inserted or removed above it. Default: the index. */
- (id<NSCopying>)virtualBox:(TRVirtualBox *)box keyForItemAtIndex:(NSInteger)index;
/* A size estimate better than estimated-size (e.g. from text length). */
- (CGFloat)virtualBox:(TRVirtualBox *)box estimatedSizeAtIndex:(NSInteger)index;
@end
```

Changes are reported, never diffed:

- `-reloadData`;
- `-insertItemsAtIndexes:`, `-removeItemsAtIndexes:`,
  `-moveItemAtIndex:toIndex:`;
- `-reloadItemsAtIndexes:` (content changed, so remeasure).

The box keeps no copy of the data.

## Sizing

The box size of an item comes from one of three places, cheapest first:

1. **Fixed:** the template's style has a definite `height` (lists) or the
   grid has definite rows. Then nothing is ever measured, and the offset
   of item *i* is arithmetic.
2. **Estimated, then measured:** the default. An item starts at its
   estimate (`estimated-size`, or the data source). When it's realized, its
   view tree is laid out by Trellis at the slot width, as any box is, and
   the real height replaces the estimate. Measured sizes are cached by
   key.
3. **Width changes:** cached heights are kept as estimates (they're closer
   than the default) and the visible items are measured again.

## The window engine (libTrellisEngine)

**TRVirtualLayout** is pure Foundation, with no views, so it is testable
with `make check`. Its inputs:

- the item count;
- the kind and template of each item (cheap);
- the container's width and its list or grid style;
- the size cache;
- the viewport (scroll offset and height) and the overscan.

Its outputs:

- **the realized range:** the visible items plus overscan, one viewport
  above and below by default (`overscan`);
- **a frame for each realized item;**
- **the total content height**, for the scroller.

How it gets them:

- **Lists:** prefix sums over item heights plus gaps. A sorted offsets
  array is rebuilt lazily after changes (10k doubles take microseconds),
  and lookups by offset are binary searches. If profiling says so, this
  becomes a Fenwick tree.
- **Grids:**
  - Columns are resolved once per width by the existing grid code, on a
    one-row probe grid with the real `grid-template-columns`, gaps and
    padding. So any column template works, not only auto-fill.
  - Items then flow into rows. An item whose template spans
    `grid-column: 1 / -1` (a group header) closes the current row and
    takes a row of its own.
  - The row table (first item and count) is rebuilt in O(n) on change.
    A row's height is the largest of its items' (measured or estimated)
    heights. Then it works like a list over rows.
- **Out of scope for v1:** other spans, dense packing, masonry,
  horizontal virtualization, and `order` on items.

## Scroll anchoring

Without anchoring, a measured item above the viewport, or an insert
above it, makes the content jump. The rule, following CSS
`overflow-anchor`:

- **Before** any change to sizes or items, record the anchor: the first
  item whose bottom is below the viewport's top, by key, and its offset
  from that top.
- **After** the change, recompute, find the anchor by key, and set the
  scroll offset so its offset from the top is unchanged.
- **If the anchor was removed,** use the next surviving item.
- **At the very top** (offset 0), stay at the top. New items at index 0
  push the content down only when the user had scrolled away from the
  top, as chat apps do.

## Reuse

- **A pool per template.** An item that leaves the realized range is
  removed from the content view, cleared by the data source on its next
  configure, and kept for reuse. The pool is capped at the realized count
  plus a margin, so memory stays flat while scrolling.
- **Container queries inside items** test the virtual box, as in
  `<scroll>` (`containerQueryParent`).

## Keyboard focus

- **Realized items join the key-view loop in index order,** after the
  views before the virtual box and before the views after it.
- **The item holding first responder is never recycled.** It stays
  realized, off-screen if need be, until focus leaves it.
- **Tab past the last realized item** scrolls the next item in, realizes
  it and focuses its first key view. The box does this with a
  zero-size sentinel view at the end of the loop, which forwards focus
  when it becomes first responder.
- **Shift-Tab** works the same way, with a sentinel at the start.
- **Arrow keys** are the app's business (selection), and so is
  `-scrollToItemAtIndex:position:`.

## Accessibility

- **Roles:** the box has role `list`, or `grid` with a column count.
  The count is the data source's, not the realized count.
- **Item positions:** each realized item records its index (and its row
  and column in a grid).
- **On Cocoa** these map to NSAccessibility: `accessibilityRowCount`,
  `accessibilityIndex`, and the list and grid roles.
- **On GNUstep** they are recorded and readable through
  `TRAccessibilityRole` and new `TRAccessibilityPosition` functions,
  as the other attributes are today.

## Tests and measurement

- **Engine cases (`make check`):**
  - list and grid offsets, row flow with spanning headers, and the
    realized range at given offsets;
  - correction after a measure, and anchoring through inserts,
    removals and remeasures (the anchor's screen position is unchanged).
- **View checks (`make check-gui`):**
  - reuse: at most realized + margin views exist while scrolling 10k items;
  - focus: Tab walks past the realized edge, and the focused item survives
    scrolling away;
  - a freed box with pending work stays clean (zombies on).
- **trellis-bench `--virtual 10000` (list and grid):**
  - time for the first layout;
  - time for each scroll step (one viewport per step);
  - views alive and peak RSS;
  - targets: well under 16.7 ms per step, and memory flat in the item
    count.
- **Dogfood:** the Work wall with 2,000 fake agents in groups, at 340,
  520, 900 and 1440. Lint clean in light and dark, with frames compared
  against the non-virtual wall at the same scroll positions.

## Order of work

1. TRVirtualLayout and its engine cases.
2. TRVirtualBox: realization, reuse, anchoring, `<virtual>` markup,
   lint (`trellis-lint` checks template ids and the data source owner
   outlet).
3. Focus and accessibility.
4. Bench, dogfood, docs (agents.md, api.md), then a minor version.

## Open questions

- **Selection** (single or multiple, highlight) could be built in.
  Proposal: no. The app owns selection, and Trellis offers a `selected`
  class toggle on realized views. That's how the Work spec already
  styles it.
- **Sticky group headers** would be nice for the wall. They're left out
  of v1, and the header-row model above doesn't block them later.
