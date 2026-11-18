# Migrating to Trellis 0.11 (draft)

## Scroll views snap to device pixels

**What changed.** When a host places a Trellis root box at a fraction of a
device pixel (for example `y = 20.5` at 1x, or `x = 10.25` at 2x), every
view in the box inherited that fraction. Scroll views then drew their
content resampled: 1px lines turned grey and pinstripes shifted. Trellis
now nudges each scroll view in the box by less than one device pixel so
its origin lands on the device grid, and puts its clip view's scroll
offset back on the grid too. On GNUstep the clip view otherwise keeps a
fractional offset it picked up while the scroll view was off the grid.

The snap runs after a layout, after an animated layout's last frame, when
the root moves to a window, and when the host moves the root without
resizing it (`-setFrameOrigin:`, or `-setFrame:` with the same size).

**What doesn't change.** Node layout frames and exported frame JSON are
unchanged, and so is every view other than the scroll views. Sizes are
unchanged. Hit testing follows the views, so it moves with the scroll
view by the same sub-pixel amount.

**What you may notice.** A scroll view's `-frame` may differ from its
layout frame by up to half a device pixel (0.5pt at 1x, 0.25pt at 2x).
Code that compares a scroll view's frame with its node's `layoutFrame`
should allow for that.

**Not covered yet.**

- Scroll views inside a split view pane or a virtual box (`TRSplitView`,
  `TRVirtualBox`) aren't snapped.
- If the host moves an ancestor of the root, not the root itself, Trellis
  isn't told. Call `-layoutTrellis` on the root after such a move. There's
  no public snap method for now.
- Only scroll views are snapped. Other views still inherit a fractional
  root origin, which matters less, because they draw directly at their
  final position.

**Workarounds that can stay.** A host that already keeps its root box on
whole pixels (a "whole pixel holder" view) can keep doing so. With such a
host the snap does nothing.
