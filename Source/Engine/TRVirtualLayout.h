/* TRVirtualLayout.h - the window engine for virtualized lists and grids.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <Foundation/Foundation.h>
#import "TRTypes.h"

@class TRStyle;

/* Lays out a long run of items without building them: only item sizes
   (estimated until measured) are kept, and the caller asks which items
   a viewport needs. See docs/design-virtualization.md.

   - List: one item per row, rows separated by row-gap.
   - Grid: columns come from the container's grid style (any
     grid-template-columns, resolved by the grid engine at the current
     width); items flow into rows, and an item that spans the full row
     (a group header) closes the current row and takes one of its own. A
     row is as tall as its tallest item.
   Offsets are in the content's coordinate space (top-left, y down),
   padding included. */

typedef NS_ENUM(NSInteger, TRVirtualMode) {
  TRVirtualModeList = 0,
  TRVirtualModeGrid
};

/* A scroll position pinned to an item: the item and how far the
   viewport's top is below that item's row top. */
typedef struct {
  NSInteger item;     /* NSNotFound when there are no items */
  TRFloat delta;
} TRVirtualAnchor;

@interface TRVirtualLayout : NSObject

- (instancetype)initWithMode:(TRVirtualMode)mode;
@property (nonatomic, readonly) TRVirtualMode mode;

/* The container's style: padding, row-gap / column-gap, and for grids
   grid-template-columns. Default: no padding, no gaps, one column. */
- (BOOL)setContainerDeclarations:(NSString *)declarations error:(NSError **)error;
/* The container's inner width minus nothing: the scroll view's width. */
@property (nonatomic) TRFloat width;

@property (nonatomic) NSInteger itemCount;
/* The size of an item never measured (default 44). */
@property (nonatomic) TRFloat estimatedSize;
/* Grids: items that take a whole row of their own (group headers).
   Asked for every item when rows are rebuilt; keep it cheap. */
@property (nonatomic, copy) BOOL (^spansFullRow)(NSInteger item);
/* A better per-item estimate than estimatedSize (optional). */
@property (nonatomic, copy) TRFloat (^estimateForItem)(NSInteger item);

/* Measured heights replace estimates. Changing the width keeps them, as
   estimates closer than the default, until measured again. */
- (void)setMeasuredHeight:(TRFloat)height forItem:(NSInteger)item;
- (BOOL)isMeasured:(NSInteger)item;
- (void)forgetMeasuredHeights;

/* Insert or remove items; sizes of the others follow them. */
- (void)insertItemsAtIndex:(NSInteger)index count:(NSInteger)count;
- (void)removeItemsAtIndex:(NSInteger)index count:(NSInteger)count;

/* Results (recomputed lazily after any change). */
@property (nonatomic, readonly) TRFloat contentHeight;
@property (nonatomic, readonly) NSInteger columnCount;
- (TRRect)frameForItem:(NSInteger)item;
/* The items to realize for a viewport [offset, offset + height]:
   whole rows that intersect it, extended by overscan viewports above
   and below. */
- (NSRange)itemsForViewportOffset:(TRFloat)offset height:(TRFloat)height
                         overscan:(TRFloat)viewports;

/* Scroll anchoring: record before a change, restore after it. */
- (TRVirtualAnchor)anchorForOffset:(TRFloat)offset;
- (TRFloat)offsetForAnchor:(TRVirtualAnchor)anchor;
/* Moves an anchor across an insert or removal (call before or after
   insertItems/removeItems with the same arguments). A removed anchor
   moves to the first item after the removed run (or the last item). */
- (TRVirtualAnchor)anchor:(TRVirtualAnchor)anchor afterInsertAt:(NSInteger)index count:(NSInteger)count;
- (TRVirtualAnchor)anchor:(TRVirtualAnchor)anchor afterRemoveAt:(NSInteger)index count:(NSInteger)count;

@end
