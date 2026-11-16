/* TRVirtualBox.h - a scroll view that builds views only for the items
   on screen (virtualized lists and grids).

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRVirtualLayout.h"

@class TRVirtualBox, TRMarkupDocument, TRMarkupElement;

/* The app's data. The box keeps no copy of it: it asks for the count,
   and fills a view (fresh or reused) whenever an item comes on screen. */
@protocol TRVirtualDataSource <NSObject>
- (NSInteger)numberOfItemsInVirtualBox:(TRVirtualBox *)box;
/* Fill a view made from the item's template. A reused view still holds
   the last item's content: set everything the template shows. */
- (void)virtualBox:(TRVirtualBox *)box configureView:(NSView *)view atIndex:(NSInteger)index;
@optional
/* The template (or factory kind) of an item; default: defaultTemplate.
   Asked for every index when rows are rebuilt, so keep it cheap. */
- (NSString *)virtualBox:(TRVirtualBox *)box templateForItemAtIndex:(NSInteger)index;
/* A better estimate than estimatedSize for an item never measured. */
- (CGFloat)virtualBox:(TRVirtualBox *)box estimatedSizeAtIndex:(NSInteger)index;
@end

typedef NS_ENUM(NSInteger, TRVirtualScrollPosition) {
  TRVirtualScrollNearest = 0,   /* the least scrolling that shows it */
  TRVirtualScrollTop,
  TRVirtualScrollCenter,
  TRVirtualScrollBottom
};

/* Markup: <virtual layout="list|grid" template="row" estimated-size="44"
   overscan="1"> with <template id="..."> children. The element's style
   (padding, gap, grid-template-columns) lays out the items; a template
   whose root has grid-column: 1 / -1 takes a whole row (group headers).
   See docs/design-virtualization.md.

   - Only items in the viewport plus `overscan` viewports above and below
     have views. A view that leaves that range goes to a pool per template
     and is reused; the item holding keyboard focus is never recycled.
   - Items are measured when they come on screen: a template's box is laid
     out at its slot width, and the height replaces the estimate. Scroll
     anchoring keeps the item at the top of the viewport still while sizes
     above it change or items are inserted or removed (at the very top,
     the view stays at the top).
   - Keyboard: on-screen items join the window's key-view loop in index
     order. Tab past the last one (or Shift-Tab before the first) scrolls
     the next item in and focuses it.
   - Accessibility: the box has role "list" or "grid" with the full item
     count (and column count); each item view records its index, row and
     column (TRAccessibilityPosition). On Cocoa these are NSAccessibility
     attributes too. */
@interface TRVirtualBox : NSScrollView <TRKeyViewProvider>

- (instancetype)initWithMode:(TRVirtualMode)mode;
@property (nonatomic, readonly) TRVirtualMode mode;
/* The window engine (read its results; don't change its items directly). */
@property (nonatomic, readonly) TRVirtualLayout *virtualLayout;

@property (nonatomic, weak) id<TRVirtualDataSource> dataSource;

/* padding, row-gap / column-gap / gap, grid-template-columns. */
- (BOOL)setContainerDeclarations:(NSString *)declarations error:(NSError **)error;
@property (nonatomic) CGFloat estimatedSize;            /* default 44 */
@property (nonatomic) CGFloat overscan;                 /* viewports, default 1 */
@property (nonatomic, copy) NSString *defaultTemplate;

/* Where item views come from: a <template id="..."> of a document (the
   kind is the template id), or a block. */
- (BOOL)registerTemplate:(NSString *)templateId ofDocument:(TRMarkupDocument *)document
                   error:(NSError **)error;
- (void)registerTemplateElement:(TRMarkupElement *)element ofDocument:(TRMarkupDocument *)document;
- (void)registerViewFactory:(NSView *(^)(void))factory forKind:(NSString *)kind;

/* Changes are reported, never diffed. */
- (void)reloadData;
- (void)insertItemsAtIndexes:(NSIndexSet *)indexes;
- (void)removeItemsAtIndexes:(NSIndexSet *)indexes;
- (void)moveItemAtIndex:(NSInteger)from toIndex:(NSInteger)to;
/* Content changed: configure the on-screen ones again and remeasure. */
- (void)reloadItemsAtIndexes:(NSIndexSet *)indexes;

- (void)scrollToItemAtIndex:(NSInteger)index position:(TRVirtualScrollPosition)position;
/* Scrolls the item in and makes its first (or last) key view first
   responder. NO if it has none. */
- (BOOL)focusItemAtIndex:(NSInteger)index last:(BOOL)last;

/* Realized views (on screen plus overscan, plus the focused item). */
- (NSView *)viewForItemAtIndex:(NSInteger)index;   /* nil if not realized */
/* The item whose view is or contains `view`; NSNotFound if none. */
- (NSInteger)indexOfItemView:(NSView *)view;
@property (nonatomic, readonly) NSIndexSet *realizedIndexes;
@property (nonatomic, readonly) NSUInteger pooledViewCount;
/* The views of the visible items, in index order (for tools). */
- (NSArray<NSView *> *)visibleItemViews;
/* Items at least partly in the viewport. */
@property (nonatomic, readonly) NSRange visibleRange;

/* Bring the views up to date now (normally done on scroll and resize). */
- (void)updateVirtualContent;

@end
