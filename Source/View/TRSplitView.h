/* TRSplitView.h - resizable panes with draggable dividers (<split>).

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

/* An NSSplitView whose panes are sized from their CSS: along the split's
 * direction, a pane's `width` (or `height`) is its starting size, its
 * `min-`/`max-` sizes limit dragging and resizing, and `flex-grow` says
 * which panes take the extra space when the split grows or shrinks (the
 * last pane when none says). The split sets each pane's frame; a pane
 * that is a TRBoxView lays out its own content.
 *
 * The divider positions can be kept: `autosave="name"` (or the autosave
 * property) stores the pane sizes in the user defaults after each drag
 * and restores them when the split first gets a size. -dividerPositions
 * and -setDividerPositions: read and set them in code.
 */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRViewMeasure.h"

typedef NS_ENUM(NSInteger, TRSplitDirection) {
  TRSplitDirectionRow = 0,     /* panes side by side, vertical dividers */
  TRSplitDirectionColumn       /* panes stacked, horizontal dividers */
};

@interface TRSplitView : NSSplitView <TRKeyViewProvider, TRSizeForWidth, NSSplitViewDelegate>

- (instancetype)initWithDirection:(TRSplitDirection)direction;
@property (nonatomic, readonly) TRSplitDirection direction;

/* Adds a pane at the end. */
- (void)addPane:(NSView *)pane;
/* All the panes, hidden ones included. */
@property (nonatomic, readonly) NSArray<NSView *> *panes;

/* Hiding a pane (markup: hidden on a pane) takes it and its divider out;
   the other panes take its space. Shown again, it comes back in its
   place at the size it had, taken from the others. Focus inside a pane
   being hidden moves to the next view. Divider positions count only the
   panes shown; autosave keeps every pane's size, hidden ones too. */
- (void)setHidden:(BOOL)hidden forPane:(NSView *)pane;
- (BOOL)isPaneHidden:(NSView *)pane;

/* Sizing along the split's direction. NAN (initial) or 0/CGFLOAT_MAX
   (min/max) mean unset. */
- (void)setInitialSize:(CGFloat)size forPane:(NSView *)pane;
- (void)setMinimumSize:(CGFloat)min maximumSize:(CGFloat)max forPane:(NSView *)pane;
- (void)setGrowWeight:(CGFloat)weight forPane:(NSView *)pane;
/* Reads width/height, min-, max- and flex-grow from a pane's style
   declarations (the loader does this for <split> children). */
- (void)setSizingFromStyle:(TRStyle *)style forPane:(NSView *)pane;

/* Divider positions: the offset of each divider from the split's leading
   (row) or top (column) edge, one fewer than the panes shown. Setting them
   clamps to the panes' limits and saves them under autosave. */
- (NSArray<NSNumber *> *)dividerPositions;
- (void)setDividerPositions:(NSArray<NSNumber *> *)positions;

/* User-defaults key suffix for the pane sizes; nil: not kept. Stored as
   "TRSplitView Panes <name>" (an array of pane sizes). */
@property (nonatomic, copy) NSString *autosave;

/* Sent to target after the user drags a divider (the positions are
   already saved). */
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;

@end
