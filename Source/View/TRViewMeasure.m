/* TRViewMeasure.m - measuring NSViews for the Trellis engine.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRViewMeasure.h"

static const CGFloat TRHuge = 100000;

static NSCell *TRCellOf(NSView *view)
{
  if ([view isKindOfClass: [NSControl class]])
    return [(NSControl *)view cell];
  return nil;
}

static BOOL TRCellWraps(NSCell *cell)
{
  return [cell type] == NSTextCellType && [cell wraps];
}

/* The size wrapping text needs at a given cell width. We do not use
   -[NSCell cellSizeForBounds:]: in libs-gui it ignores the width (it is a
   TODO that returns -cellSize). Instead: lay the attributed string out at
   the text width, and add the cell's own insets (cellSize minus the
   single-line text size). */
static NSSize TRWrappedCellSize(NSCell *cell, CGFloat cellWidth)
{
  NSSize full = [cell cellSize];
  NSAttributedString *as = [cell attributedStringValue];
  if ([as length] == 0) return full;
  NSRect one = [as boundingRectWithSize: NSMakeSize(TRHuge, TRHuge)
                                options: NSStringDrawingUsesLineFragmentOrigin];
  CGFloat insetW = MAX(0, full.width - ceil(NSWidth(one)));
  CGFloat insetH = MAX(0, full.height - ceil(NSHeight(one)));
  CGFloat textW = MAX(1, cellWidth - insetW);
  NSRect r = [as boundingRectWithSize: NSMakeSize(textW, TRHuge)
                              options: NSStringDrawingUsesLineFragmentOrigin];
  return NSMakeSize(ceil(NSWidth(r)) + insetW, ceil(NSHeight(r)) + insetH);
}

/* libs-gui's NSSliderCell has no -cellSize of its own, so it inherits
   NSCell's border-only {8, 4} and a slider would get a 4pt-tall frame:
   enough for a thin track, but a theme with a real knob (Gumdrop scales its
   art to the frame) draws nothing. Give the cross axis Cocoa's regular
   slider thickness: 21pt, or 26 with tick marks. Apple's -cellSize is
   already right there.
   Along the track, Apple's -cellSize reports a huge length (40000) meaning
   "flexible", as -intrinsicContentSize's NSViewNoIntrinsicMetric does, so
   Trellis treats it as no intrinsic length (GNUstep reports 8). */
NSSize TRCellSize(NSCell *cell)
{
  NSSize s = [cell cellSize];
  if ([cell isKindOfClass: [NSSliderCell class]])
    {
      NSSliderCell *sc = (NSSliderCell *)cell;
      BOOL vertical = ([sc isVertical] == 1);
      CGFloat *along = vertical ? &s.height : &s.width;
      if (*along >= 10000) *along = 0;
#ifdef GNUSTEP
      CGFloat cross = [sc numberOfTickMarks] > 0 ? 26 : 21;
      if (vertical) s.width = MAX(s.width, cross);
      else s.height = MAX(s.height, cross);
#endif
    }
  return s;
}

TRSize TRMeasureView(NSView *view, TRSize available, TRMeasureMode wm, TRMeasureMode hm)
{
  if (view == nil) return TRSizeMake(0, 0);
  if ([view respondsToSelector: @selector(trellisSizeForWidth:)])
    {
      CGFloat w = (wm == TRMeasureModeUndefined || isnan(available.width)) ? CGFLOAT_MAX : available.width;
      NSSize s = [(id<TRSizeForWidth>)view trellisSizeForWidth: w];
      return TRSizeMake(ceil(s.width), ceil(s.height));
    }
  NSCell *cell = TRCellOf(view);
  if (cell != nil)
    {
      NSSize s = TRCellSize(cell);
      if (TRCellWraps(cell) && wm != TRMeasureModeUndefined && available.width < s.width)
        {
          NSSize ws = TRWrappedCellSize(cell, available.width);
          s = NSMakeSize(MIN(ws.width, s.width), ws.height);
        }
      return TRSizeMake(ceil(s.width), ceil(s.height));
    }
  NSSize ic = [view intrinsicContentSize];
  return TRSizeMake(ic.width == NSViewNoIntrinsicMetric ? 0 : ic.width,
                    ic.height == NSViewNoIntrinsicMetric ? 0 : ic.height);
}

TRFloat TRBaselineOfView(NSView *view, TRSize size)
{
  NSCell *cell = TRCellOf(view);
  NSFont *font = [cell font];
  if (cell == nil || font == nil) return size.height;
  NSRect bounds = NSMakeRect(0, 0, size.width, size.height);
  CGFloat lineH0 = [font ascender] - [font descender];
  /* Push buttons and pop-ups draw their single-line title centred in the
     whole bezel (GNUstep themes and Aqua alike); their title rects are not
     reliable for this. */
  if ([view isKindOfClass: [NSPopUpButton class]]
      || ([view isKindOfClass: [NSButton class]] && [cell isBezeled]))
    return floor((size.height - lineH0) / 2) + [font ascender];
  NSRect title = [cell titleRectForBounds: bounds];
  /* Text inside the title rect is vertically centred on GNUstep and Apple
     for single-line cells. */
  CGFloat lineH = [font ascender] - [font descender];
  CGFloat top = [view isFlipped] ? NSMinY(title) : size.height - NSMaxY(title);
  if (!TRCellWraps(cell)) top += MAX(0, (NSHeight(title) - lineH) / 2);
  return top + [font ascender];
}

NSString *TRContentSignature(NSView *view)
{
  NSCell *cell = TRCellOf(view);
  if (cell != nil)
    {
      NSFont *f = [cell font];
      NSString *text = [cell type] == NSTextCellType ? [cell stringValue] : @"";
      NSString *title = [cell respondsToSelector: @selector(title)] ? [(id)cell title] : @"";
      return [NSString stringWithFormat: @"%@|%@|%@|%g|%d", text, title ?: @"",
                       [f fontName] ?: @"", [f pointSize], (int)[cell wraps]];
    }
  NSSize ic = [view intrinsicContentSize];
  return [NSString stringWithFormat: @"%g,%g", ic.width, ic.height];
}

BOOL TRViewIsClipped(NSView *view, NSSize *needed)
{
  NSCell *cell = TRCellOf(view);
  if (cell == nil) return NO;
  NSSize fs = [view frame].size;
  NSSize s;
  if (TRCellWraps(cell))
    {
      s = TRWrappedCellSize(cell, fs.width);
      s.width = MIN(s.width, fs.width);   /* wrapped text is as wide as its box */
    }
  else
    s = TRCellSize(cell);
  if (needed) *needed = s;
  return s.width > fs.width + 0.5 || s.height > fs.height + 0.5;
}
