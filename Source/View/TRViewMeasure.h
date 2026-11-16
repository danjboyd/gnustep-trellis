/* TRViewMeasure.h - measuring NSViews for the Trellis engine.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <AppKit/AppKit.h>
#import "TrellisEngine.h"

/* The content size of a leaf view under a Trellis constraint:
   - cell-based controls: -[NSCell cellSize], or -cellSizeForBounds: at the
     proposed width for wrapping text;
   - other views: intrinsicContentSize where defined, otherwise 0. */
TRSize TRMeasureView(NSView *view, TRSize available, TRMeasureMode wm, TRMeasureMode hm);

/* A cell's intrinsic size as Trellis sees it: -cellSize with the slider
   corrections (no intrinsic length along a Cocoa track; GNUstep thickness). */
NSSize TRCellSize(NSCell *cell);

/* First baseline from the top of the view, at the given size. */
TRFloat TRBaselineOfView(NSView *view, TRSize size);

/* A string that changes when the view's measured content may change. */
NSString *TRContentSignature(NSView *view);

/* YES if the view's content does not fit its current frame; fills *needed
   with the size it needs. */
BOOL TRViewIsClipped(NSView *view, NSSize *needed);
