# Known issues

## GNUstep (libs-gui)

- **`-[NSCell cellSizeForBounds:]` ignores the width.** It is a stub that
  returns `-cellSize` (libs-gui `Source/NSCell.m:2002`, `// TODO: Resize the
  text to fit`, master 662f890). Trellis measures wrapping text with
  `-[NSAttributedString boundingRectWithSize:options:]` plus the cell's own
  insets instead (`Source/View/TRViewMeasure.m`). Possibly worth an
  upstream issue, filed through upstream.propose. Nothing has been filed.
- `_NET_WORKAREA` warnings on stderr under bare Xvfb (no window manager)
  are harmless.

## Trellis

- **Baselines of pop-up buttons** are a few px off under Adwaita: labels
  aligned with `align-items: baseline` sit about 3 px above the pop-up
  text. `TRBaselineOfView` centres the font's line box in the cell's
  title rect, and themed pop-up cells draw their title differently.
  Needs a per-cell-class baseline, or a theme hook.
- `display: block` is a column flex container, not CSS block flow (see
  design.md section 4a).
- Absolute positioning is relative to the parent box, not the nearest
  positioned ancestor.
- Logical properties (`margin-inline-start` and so on) are mapped as if
  left-to-right.
