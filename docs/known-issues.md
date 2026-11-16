# Known issues

## GNUstep (libs-gui)

- **`-[NSCell cellSizeForBounds:]` ignores the width.** It is a stub that
  returns `-cellSize` (libs-gui `Source/NSCell.m:2002`, `// TODO: Resize the
  text to fit`, master 662f890). Trellis measures wrapping text with
  `-[NSAttributedString boundingRectWithSize:options:]` plus the cell's own
  insets instead (`Source/View/TRViewMeasure.m`). Reproducer:
  Tests/Upstream/cellsize-for-bounds.m (plain MRC Objective-C, no blocks;
  prints FAIL against the libs-gui in our toolchain: 286x15 either way). Possibly worth an upstream issue, filed through
  upstream.propose. Nothing has been filed.
- **`NSSliderCell` has no `-cellSize`,** so it inherits NSCell's border-only
  {8, 4} and a slider would get a 4pt-tall frame. Trellis floors a slider's
  cross axis at Cocoa's regular thickness (21pt, 26 with tick marks) on
  GNUstep (`TRCellSize` in `Source/View/TRViewMeasure.m`). Before that,
  Gumdrop, which scales its slider art to the frame, drew no slider at all.
  Reproducer: Tests/Upstream/slider-cellsize.m (plain MRC Objective-C;
  prints FAIL: 8x4, knobThickness 0). Possibly worth an upstream issue,
  filed through upstream.propose. Nothing has been filed.
- The two reproducers are written to build with GCC (no ARC, no blocks)
  but haven't been compiled with it yet: this VM's gcc has no Objective-C
  front end (gobjc). Both build and fail as expected with clang.
- `_NET_WORKAREA` warnings on stderr under bare Xvfb (no window manager)
  are harmless.

- **Text-field cells wrap by default on GNUstep** (Apple's labels don't).
  The loader sets `wraps` explicitly on every label and field, so layout
  and lint behave the same on both platforms.
- **No accessibility API on views.** GNUstep's AppKit declares the
  NSAccessibility protocols, but NSView and the controls implement none of
  the setters (`setAccessibilityLabel:`, `setAccessibilityTitleUIElement:`,
  `setAccessibilityRole:`, `setAccessibilityElement:`), and there's no
  bridge to AT-SPI. Trellis records `a11y-label`, `label-for` and `role`
  (readable with `TRAccessibilityLabel` and friends) and sets them on
  NSAccessibility only where the selectors exist, so they take effect on
  Cocoa today and on GNUstep once libs-gui gains them.
- **NSScanner** on GNUstep doesn't skip leading whitespace when a scan
  fails; Apple's does. Trellis parsers avoid NSScanner for multi-token
  input.

## Trellis

- **Baselines of buttons and pop-ups** are computed by centring the font line box in the bezel (fixed 2026-11-13; it was about 3 px off under Adwaita).
- `display: block` is a column flex container, not CSS block flow (see
  design.md section 4a).
- Absolute positioning is relative to the parent box, not the nearest
  positioned ancestor.
- Logical properties (`margin-inline-start` and so on) are mapped as if
  left-to-right.
