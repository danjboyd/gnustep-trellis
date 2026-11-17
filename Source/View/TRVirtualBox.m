/* TRVirtualBox.m - a scroll view that builds views only for the items
   on screen (virtualized lists and grids).

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRVirtualBox.h"
#import "TRLoader.h"
#import "TRViewMeasure.h"
#import "TRStyle.h"

/* The document view: flipped, so offsets read top-down as in the engine. */
@interface TRVirtualDocView : NSView
@end
@implementation TRVirtualDocView
- (BOOL)isFlipped { return YES; }
@end

/* Zero-size views at both ends of the box's part of the key-view loop.
   When focus lands on one, the box scrolls the next item in and moves
   focus there (or past the box at the ends). */
@interface TRVirtualSentinel : NSView
{
@public
  __weak TRVirtualBox *box;
  BOOL tail;
  NSSelectionDirection direction;
}
@end

@interface TRVirtualBox ()
- (void)sentinel:(TRVirtualSentinel *)s arrivedBackward:(BOOL)backward;
- (BOOL)sentinelsActive;
@end

@implementation TRVirtualSentinel
- (BOOL)acceptsFirstResponder { return [box sentinelsActive]; }
- (BOOL)canBecomeKeyView { return ![self isHiddenOrHasHiddenAncestor] && [box sentinelsActive]; }
/* Which way focus came: Cocoa knows while making the sentinel first
   responder; GNUstep only around the -selectText: that follows. */
- (BOOL)becomeFirstResponder
{
  direction = [[self window] keyViewSelectionDirection];
  /* Move focus on from the run loop, not from inside -makeFirstResponder:
     (GNUstep records the sentinel as first responder only after this
     returns; Cocoa already has, but nesting focus changes is unsafe). */
  [self performSelector: @selector(forward) withObject: nil afterDelay: 0];
  return YES;
}
- (void)selectText:(id)sender
{
  NSSelectionDirection d = [[self window] keyViewSelectionDirection];
  if (d != NSDirectSelection) direction = d;
}
- (void)forward
{
  if ([[self window] firstResponder] != self || direction == NSDirectSelection) return;
  [box sentinel: self arrivedBackward: direction == NSSelectingPrevious];
}
@end

/* How an item view is made. */
@interface TRVirtualKind : NSObject
{
@public
  TRMarkupElement *element;
  TRMarkupDocument *document;
  NSView *(^factory)(void);
  BOOL spansRow;
  NSMutableArray<NSView *> *pool;
}
@end
@implementation TRVirtualKind
@end

@implementation TRVirtualBox
{
  TRVirtualMode _mode;
  TRVirtualLayout *_layout;
  TRVirtualDocView *_doc;
  TRVirtualSentinel *_head, *_tail;
  NSMutableDictionary<NSString *, TRVirtualKind *> *_kinds;
  NSMutableDictionary<NSNumber *, NSView *> *_realized;    /* index -> view */
  NSMapTable *_viewKinds;                                  /* view -> kind name */
  BOOL _needsReload, _updating, _hasKeyViews, _keyLoopDirty;
  NSRange _visible, _loopVisible;
  __weak NSView *_lastFocused;
  NSInteger _focusIndex;   /* the item that last held focus, or NSNotFound */
}

- (instancetype)initWithMode:(TRVirtualMode)mode
{
  if ((self = [super initWithFrame: NSMakeRect(0, 0, 100, 100)]) != nil)
    {
      _mode = mode;
      _layout = [[TRVirtualLayout alloc] initWithMode: mode];
      _overscan = 1;
      _defaultTemplate = @"item";
      _kinds = [NSMutableDictionary dictionary];
      _realized = [NSMutableDictionary dictionary];
      _viewKinds = [NSMapTable weakToStrongObjectsMapTable];
      _doc = [[TRVirtualDocView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
      _focusIndex = NSNotFound;
      _head = [[TRVirtualSentinel alloc] initWithFrame: NSZeroRect];
      _head->box = self;
      _tail = [[TRVirtualSentinel alloc] initWithFrame: NSZeroRect];
      _tail->box = self;
      _tail->tail = YES;
      [_doc addSubview: _head];
      [_doc addSubview: _tail];
      [self setHasVerticalScroller: YES];
      [self setHasHorizontalScroller: NO];
      [self setBorderType: NSNoBorder];
      [self setDrawsBackground: NO];
      [self setDocumentView: _doc];
      _needsReload = YES;
      __weak TRVirtualBox *weakSelf = self;
      _layout.spansFullRow = ^BOOL (NSInteger i) {
        TRVirtualBox *s = weakSelf;
        return s ? s->_kinds[[s kindForItem: i]]->spansRow : NO;
      };
      [self updateAccessibility];
    }
  return self;
}

- (instancetype)initWithFrame:(NSRect)frame
{
  if ((self = [self initWithMode: TRVirtualModeList]) != nil)
    [self setFrame: frame];
  return self;
}

- (void)dealloc
{
  [NSObject cancelPreviousPerformRequestsWithTarget: _head];
  [NSObject cancelPreviousPerformRequestsWithTarget: _tail];
  _head->box = nil;
  _tail->box = nil;
}

- (TRVirtualMode)mode { return _mode; }
- (TRVirtualLayout *)virtualLayout { return _layout; }

- (BOOL)setContainerDeclarations:(NSString *)declarations error:(NSError **)error
{
  if (![_layout setContainerDeclarations: declarations error: error]) return NO;
  [self updateVirtualContent];
  return YES;
}

- (CGFloat)estimatedSize { return _layout.estimatedSize; }
- (void)setEstimatedSize:(CGFloat)size { _layout.estimatedSize = size; }

- (void)setDataSource:(id<TRVirtualDataSource>)ds
{
  _dataSource = ds;
  __weak TRVirtualBox *weakSelf = self;
  if ([ds respondsToSelector: @selector(virtualBox:estimatedSizeAtIndex:)])
    _layout.estimateForItem = ^TRFloat (NSInteger i) {
      TRVirtualBox *s = weakSelf;
      return s ? [s->_dataSource virtualBox: s estimatedSizeAtIndex: i] : 44;
    };
  else
    _layout.estimateForItem = nil;
  [self reloadData];
}

/* ---- Kinds ---- */

static BOOL TRSpansRow(TRMarkupElement *e, TRMarkupDocument *doc)
{
  if (e == nil) return NO;
  TRStyle *st = [TRStyle new];
  for (TRMatchedDeclarations *m in [doc declarationsForElement: e])
    if (m.condition == nil) [st applyDeclarations: m.declarations error: NULL];
  NSString *a = [st->_gridColumnStart stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
  NSString *b = [st->_gridColumnEnd stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
  return [a isEqualToString: @"1"] && [b isEqualToString: @"-1"];
}

- (TRVirtualKind *)addKind:(NSString *)name
{
  TRVirtualKind *k = _kinds[name];
  if (k == nil)
    {
      k = [TRVirtualKind new];
      k->pool = [NSMutableArray array];
      _kinds[name] = k;
    }
  for (NSView *v in k->pool) [_viewKinds removeObjectForKey: v];
  [k->pool removeAllObjects];
  return k;
}

- (void)registerTemplateElement:(TRMarkupElement *)element ofDocument:(TRMarkupDocument *)doc
{
  NSString *tid = element.attributes[@"id"];
  if (tid == nil) return;
  TRVirtualKind *k = [self addKind: tid];
  k->element = element;
  k->document = doc;
  k->factory = nil;
  k->spansRow = [element.children count] == 1 ? TRSpansRow(element.children[0], doc) : NO;
  _needsReload = YES;
}

- (BOOL)registerTemplate:(NSString *)templateId ofDocument:(TRMarkupDocument *)doc error:(NSError **)error
{
  TRMarkupElement *t = doc.templates[templateId];
  if (t == nil || [t.children count] != 1)
    {
      if (error) *error = [NSError errorWithDomain: TRMarkupErrorDomain code: 11 userInfo: @{
        NSLocalizedDescriptionKey: [NSString stringWithFormat: @"%@: no <template id=\"%@\"> with exactly one child",
                                     doc.name, templateId]}];
      return NO;
    }
  [self registerTemplateElement: t ofDocument: doc];
  return YES;
}

- (void)registerViewFactory:(NSView *(^)(void))factory forKind:(NSString *)kind
{
  TRVirtualKind *k = [self addKind: kind];
  k->element = nil;
  k->document = nil;
  k->factory = [factory copy];
  k->spansRow = NO;
  _needsReload = YES;
}

- (NSString *)kindForItem:(NSInteger)i
{
  NSString *k = nil;
  if ([_dataSource respondsToSelector: @selector(virtualBox:templateForItemAtIndex:)])
    k = [_dataSource virtualBox: self templateForItemAtIndex: i];
  if (k == nil || _kinds[k] == nil) k = _defaultTemplate;
  if (_kinds[k] == nil && [_kinds count] == 1) k = [[_kinds allKeys] firstObject];
  return k;
}

- (NSView *)makeViewOfKind:(NSString *)name
{
  TRVirtualKind *k = _kinds[name];
  if (k == nil) return nil;
  if ([k->pool count])
    {
      NSView *v = [k->pool lastObject];
      [k->pool removeLastObject];
      return v;
    }
  NSView *v = nil;
  if (k->factory) v = k->factory();
  else if (k->element)
    {
      NSError *err = nil;
      v = [TRLoader instantiateTemplateElement: k->element ofDocument: k->document error: &err];
      if (v == nil) NSLog(@"TRVirtualBox: template '%@': %@", name, [err localizedDescription]);
    }
  if (v == nil) return nil;
  /* Item boxes are roots of their own, inside the window's loop. */
  if ([v isKindOfClass: [TRBoxView class]]) [(TRBoxView *)v setManagesKeyViewLoop: NO];
  [_viewKinds setObject: name forKey: v];
  return v;
}

/* ---- Changes ---- */

- (void)syncCount
{
  NSInteger n = _dataSource ? [_dataSource numberOfItemsInVirtualBox: self] : 0;
  _layout.itemCount = MAX(n, 0);
  _needsReload = NO;
}

- (void)recycleView:(NSView *)v
{
  _keyLoopDirty = YES;
  NSString *name = [_viewKinds objectForKey: v];
  TRVirtualKind *k = name ? _kinds[name] : nil;
  [v removeFromSuperview];
  /* The pool holds at most as many as are on screen, plus a margin. */
  if (k && [k->pool count] < [_realized count] + 8) [k->pool addObject: v];
  else [_viewKinds removeObjectForKey: v];
}

- (void)reloadData
{
  [self withAnchor: ^{
    for (NSNumber *i in [_realized allKeys]) [self recycleView: _realized[i]];
    [_realized removeAllObjects];
    [_layout forgetMeasuredHeights];
    [self syncCount];
  } keep: NO];
  [self updateAccessibility];
}

/* Runs a change to items or sizes with the scroll position anchored to
   the item at the top of the viewport (unless at the very top). */
- (void)withAnchor:(void (^)(void))change keep:(BOOL)keep
{
  [self withAnchor: change adjust: nil keep: keep];
}

- (void)withAnchor:(void (^)(void))change adjust:(TRVirtualAnchor (^)(TRVirtualAnchor))adjust keep:(BOOL)keep
{
  if (_needsReload && keep) [self syncCount];
  CGFloat offset = [[self contentView] bounds].origin.y;
  BOOL atTop = offset <= 0.5 || !keep;
  TRVirtualAnchor a = atTop ? (TRVirtualAnchor){ NSNotFound, 0 } : [_layout anchorForOffset: offset];
  change();
  if (adjust && a.item != NSNotFound) a = adjust(a);
  [self updateWithAnchor: a use: !atTop && a.item != NSNotFound];
}

/* The runs of an index set, in order (portable: no block enumeration). */
static NSArray<NSValue *> *TRRuns(NSIndexSet *set)
{
  NSMutableArray *out = [NSMutableArray array];
  NSUInteger i = [set firstIndex];
  while (i != NSNotFound)
    {
      NSUInteger j = i;
      while ([set containsIndex: j + 1]) j++;
      [out addObject: [NSValue valueWithRange: NSMakeRange(i, j - i + 1)]];
      i = [set indexGreaterThanIndex: j];
    }
  return out;
}

static void TRShiftRealized(NSMutableDictionary *realized, NSInteger from, NSInteger by)
{
  NSMutableDictionary *moved = [NSMutableDictionary dictionary];
  for (NSNumber *k in [realized allKeys])
    if ([k integerValue] >= from)
      {
        moved[@([k integerValue] + by)] = realized[k];
        [realized removeObjectForKey: k];
      }
  [realized addEntriesFromDictionary: moved];
}

- (void)insertItemsAtIndexes:(NSIndexSet *)indexes
{
  if (_needsReload) { [self reloadData]; return; }
  for (NSValue *run in TRRuns(indexes))
    {
    NSRange r = [run rangeValue];
    NSInteger at = (NSInteger)r.location, n = (NSInteger)r.length;
    [self withAnchor: ^{
      TRShiftRealized(_realized, at, n);
      if (_focusIndex != NSNotFound && _focusIndex >= at) _focusIndex += n;
      _keyLoopDirty = YES;
      [_layout insertItemsAtIndex: at count: n];
    } adjust: ^TRVirtualAnchor (TRVirtualAnchor a) {
      return [_layout anchor: a afterInsertAt: at count: n];
    } keep: YES];
    }
  [self updateAccessibility];
}

- (void)removeItemsAtIndexes:(NSIndexSet *)indexes
{
  if (_needsReload) { [self reloadData]; return; }
  for (NSValue *run in [TRRuns(indexes) reverseObjectEnumerator])
    {
    NSRange r = [run rangeValue];
    NSInteger at = (NSInteger)r.location, n = (NSInteger)r.length;
    [self withAnchor: ^{
      for (NSInteger i = at; i < at + n; i++)
        {
          NSView *v = _realized[@(i)];
          if (v) { [self recycleView: v]; [_realized removeObjectForKey: @(i)]; }
        }
      TRShiftRealized(_realized, at + n, -n);
      if (_focusIndex != NSNotFound)
        {
          if (_focusIndex >= at + n) _focusIndex -= n;
          else if (_focusIndex >= at) _focusIndex = NSNotFound;
        }
      _keyLoopDirty = YES;
      [_layout removeItemsAtIndex: at count: n];
    } adjust: ^TRVirtualAnchor (TRVirtualAnchor a) {
      return [_layout anchor: a afterRemoveAt: at count: n];
    } keep: YES];
    }
  [self updateAccessibility];
}

- (void)moveItemAtIndex:(NSInteger)from toIndex:(NSInteger)to
{
  if (from == to) return;
  [self removeItemsAtIndexes: [NSIndexSet indexSetWithIndex: (NSUInteger)from]];
  [self insertItemsAtIndexes: [NSIndexSet indexSetWithIndex: (NSUInteger)to]];
}

- (void)reloadItemsAtIndexes:(NSIndexSet *)indexes
{
  [self withAnchor: ^{
    for (NSUInteger i = [indexes firstIndex]; i != NSNotFound; i = [indexes indexGreaterThanIndex: i])
    {
      NSView *v = _realized[@(i)];
      if (v == nil) continue;
      /* A template change means a different view. */
      if (![[_viewKinds objectForKey: v] isEqualToString: [self kindForItem: (NSInteger)i]])
        {
          [self recycleView: v];
          [_realized removeObjectForKey: @(i)];
          continue;
        }
      [_dataSource virtualBox: self configureView: v atIndex: (NSInteger)i];
      [self measureView: v atIndex: (NSInteger)i];
    }
  } keep: YES];
}

/* ---- Realization ---- */

- (CGFloat)measureView:(NSView *)v atIndex:(NSInteger)i
{
  CGFloat w = [_layout widthForItem: i];
  CGFloat h;
  if ([v isKindOfClass: [TRBoxView class]])
    h = [(TRBoxView *)v heightForWidth: w];
  else if ([v respondsToSelector: @selector(trellisSizeForWidth:)])
    h = [(id<TRSizeForWidth>)v trellisSizeForWidth: w].height;
  else
    h = TRMeasureView(v, TRSizeMake(w, NAN), TRMeasureModeExactly, TRMeasureModeUndefined).height;
  h = ceil(h);
  [_layout setMeasuredHeight: h forItem: i];
  return h;
}

- (NSView *)focusedItemView
{
  NSResponder *r = [[self window] firstResponder];
  if ([r isKindOfClass: [NSText class]] && [(NSText *)r isFieldEditor]
      && [[(NSText *)r delegate] isKindOfClass: [NSView class]])
    r = (NSView *)[(NSText *)r delegate];
  if (![r isKindOfClass: [NSView class]]) return nil;
  for (NSNumber *k in _realized)
    if ([(NSView *)r isDescendantOf: _realized[k]]) return _realized[k];
  return nil;
}

- (void)updateVirtualContent
{
  if (_needsReload) [self syncCount];
  [self updateWithAnchor: (TRVirtualAnchor){ NSNotFound, 0 } use: NO];
}

- (void)updateWithAnchor:(TRVirtualAnchor)anchor use:(BOOL)use
{
  if (_updating) return;
  _updating = YES;
  if (_needsReload) [self syncCount];
  NSSize cs = [self contentSize];
  _layout.width = cs.width;
  CGFloat offset = [[self contentView] bounds].origin.y;
  NSRange r = NSMakeRange(0, 0);
  for (int pass = 0; pass < 4; pass++)
    {
      if (use) offset = [_layout offsetForAnchor: anchor];
      offset = MAX(0, MIN(offset, _layout.contentHeight - cs.height));
      r = [_layout itemsForViewportOffset: offset height: cs.height overscan: _overscan];
      BOOL changed = NO;
      for (NSUInteger i = r.location; i < NSMaxRange(r); i++)
        {
          NSView *v = _realized[@(i)];
          BOOL fresh = (v == nil);
          if (fresh)
            {
              v = [self makeViewOfKind: [self kindForItem: (NSInteger)i]];
              if (v == nil) continue;
              _realized[@(i)] = v;
              _keyLoopDirty = YES;
              [_dataSource virtualBox: self configureView: v atIndex: (NSInteger)i];
              [_doc addSubview: v];
              /* Container queries in an item test the box's containers. */
              if ([v isKindOfClass: [TRBoxView class]])
                ((TRBoxView *)v).node.containerQueryParent = [self queryParent];
            }
          if (fresh || ![_layout isMeasured: (NSInteger)i])
            {
              CGFloat old = [_layout heightForItem: (NSInteger)i];
              if ([self measureView: v atIndex: (NSInteger)i] != old) changed = YES;
            }
        }
      if (!changed) break;
      if (!use)
        {
          /* Sizes above the viewport changed: keep its top item still. */
          if (offset > 0.5) { anchor = [_layout anchorForOffset: offset]; use = YES; }
        }
    }
  /* Recycle what left the range, except the focused item. */
  NSView *focused = [self focusedItemView];
  if (focused != _lastFocused) { _lastFocused = focused; _keyLoopDirty = YES; }
  if (focused != nil) _focusIndex = [self indexOfItemView: focused];
  for (NSNumber *k in [_realized allKeys])
    {
      NSInteger i = [k integerValue];
      if (NSLocationInRange((NSUInteger)i, r) && i < _layout.itemCount) continue;
      NSView *v = _realized[k];
      if (v == focused && i < _layout.itemCount) continue;
      [self recycleView: v];
      [_realized removeObjectForKey: k];
    }
  /* Place. */
  CGFloat ch = MAX(_layout.contentHeight, cs.height);
  [_doc setFrameSize: NSMakeSize(cs.width, ch)];
  for (NSNumber *k in _realized)
    {
      NSInteger i = [k integerValue];
      NSView *v = _realized[k];
      TRRect f = [_layout frameForItem: i];
      NSRect nf = NSMakeRect(f.x, f.y, f.width, f.height);
      if (!NSEqualRects([v frame], nf)) [v setFrame: nf];
      if ([v isKindOfClass: [TRBoxView class]]) [(TRBoxView *)v layoutTrellis];
      if (_mode == TRVirtualModeGrid)
        {
          NSInteger col = 0, row = [_layout rowForItem: i column: &col];
          TRSetAccessibilityPosition(v, i, row, col);
        }
      else
        TRSetAccessibilityPosition(v, i, i, 0);
    }
  /* Sentinels just outside the visible items. */
  _visible = [self computeVisibleRangeAt: offset height: cs.height];
  CGFloat top = _visible.length ? [_layout frameForItem: (NSInteger)_visible.location].y : offset;
  CGFloat bottom = _visible.length ? NSMaxY([self rectOfItem: (NSInteger)NSMaxRange(_visible) - 1]) : offset;
  [_head setFrame: NSMakeRect(0, top, 0, 0)];
  [_tail setFrame: NSMakeRect(0, bottom, 0, 0)];
  if (fabs([[self contentView] bounds].origin.y - offset) > 0.25)
    {
      [[self contentView] scrollToPoint: NSMakePoint(0, offset)];
      [self reflectScrolledClipView: [self contentView]];
    }
  _updating = NO;
  if (_keyLoopDirty || !NSEqualRanges(_visible, _loopVisible))
    {
      _loopVisible = _visible;
      _keyLoopDirty = NO;
      [self relinkKeyViews];
    }
}

- (TRNode *)queryParent
{
  NSView *sv = [self superview];
  return [sv isKindOfClass: [TRBoxView class]] ? [(TRBoxView *)sv nodeForSubview: self] : nil;
}

- (NSRect)rectOfItem:(NSInteger)i
{
  TRRect f = [_layout frameForItem: i];
  return NSMakeRect(f.x, f.y, f.width, f.height);
}

- (NSRange)computeVisibleRangeAt:(CGFloat)offset height:(CGFloat)h
{
  NSRange r = [_layout itemsForViewportOffset: offset height: h overscan: 0];
  return r;
}

- (NSRange)visibleRange { return _visible; }

- (void)relinkKeyViews
{
  for (NSView *p = [self superview]; p != nil; p = [p superview])
    if ([p isKindOfClass: [TRBoxView class]])
      {
        [[(TRBoxView *)p rootBox] recalculateTrellisKeyViewLoop];
        return;
      }
}

- (void)updateAccessibility
{
  TRSetAccessibilityCollection(self, _mode == TRVirtualModeGrid ? @"grid" : @"list",
                               _layout.itemCount, _mode == TRVirtualModeGrid ? _layout.columnCount : 0);
}

/* ---- Keyboard ---- */

- (NSArray<NSView *> *)trellisKeyViewSubtrees
{
  NSMutableArray *out = [NSMutableArray array];
  [out addObject: _head];
  NSView *focused = [self focusedItemView];
  NSArray *keys = [[_realized allKeys] sortedArrayUsingSelector: @selector(compare:)];
  BOOL any = NO;
  for (NSNumber *k in keys)
    {
      NSView *v = _realized[k];
      if (!NSLocationInRange([k unsignedIntegerValue], _visible) && v != focused) continue;
      [out addObject: v];
      any = YES;
    }
  _hasKeyViews = any && [self itemHasKeyViews];
  [out addObject: _tail];
  return out;
}

static void TRAddKeyViews(NSView *v, NSMutableArray *out)
{
  if ([v isHidden]) return;
  if ([v isKindOfClass: [TRBoxView class]])
    {
      for (TRNode *c in ((TRBoxView *)v).node.children)
        if ([c.context isKindOfClass: [NSView class]]) TRAddKeyViews(c.context, out);
      return;
    }
  if ([v canBecomeKeyView] || [v acceptsFirstResponder])
    {
      if (TRTabIndex(v) >= 0) [out addObject: v];
      return;
    }
  for (NSView *s in [v subviews]) TRAddKeyViews(s, out);
}

- (BOOL)itemHasKeyViews
{
  for (NSNumber *k in _realized)
    {
      NSMutableArray *a = [NSMutableArray array];
      TRAddKeyViews(_realized[k], a);
      if ([a count]) return YES;
    }
  return NO;
}

/* Whether AppKit itself can move focus between the items' controls. */
- (BOOL)itemKeyViewsAreValid
{
  for (NSNumber *k in _realized)
    {
      NSMutableArray *a = [NSMutableArray array];
      TRAddKeyViews(_realized[k], a);
      for (NSView *v in a) if ([v canBecomeKeyView]) return YES;
      if ([a count]) return NO;
    }
  return NO;
}

- (BOOL)sentinelsActive
{
  return _hasKeyViews && _layout.itemCount > 0;
}

- (BOOL)focusItemAtIndex:(NSInteger)index last:(BOOL)last
{
  if (index < 0 || index >= _layout.itemCount) return NO;
  [self scrollToItemAtIndex: index position: TRVirtualScrollNearest];
  NSView *v = _realized[@(index)];
  if (v == nil) return NO;
  NSMutableArray *a = [NSMutableArray array];
  TRAddKeyViews(v, a);
  if ([a count] == 0) return NO;
  BOOL ok = [[self window] makeFirstResponder: last ? [a lastObject] : a[0]];
  /* The loop follows the focused item (an off-screen one stays in it). */
  [self relinkKeyViews];
  _lastFocused = v;
  _focusIndex = index;
  return ok;
}

- (void)sentinel:(TRVirtualSentinel *)s arrivedBackward:(BOOL)backward
{
  NSWindow *w = [self window];
  NSInteger n = _layout.itemCount;
  NSInteger first = _visible.length ? (NSInteger)_visible.location : 0;
  NSInteger last = _visible.length ? (NSInteger)NSMaxRange(_visible) - 1 : -1;
  /* Leaving through an edge. When the items' controls are valid key views
     (GNUstep; Cocoa with full keyboard access), AppKit moves focus between
     them itself and reaches a sentinel only from the edge item, so step
     from the edge. When they aren't (Cocoa buttons without full keyboard
     access), every Tab lands on a sentinel straight from the focused item,
     and only Trellis moves focus, so _focusIndex is current: step from
     there, or the visible items in between would be skipped. */
  NSInteger from = _focusIndex;
  if (from != NSNotFound && from < n && _realized[@(from)] != nil && ![self itemKeyViewsAreValid])
    {
      if (!s->tail && backward) first = from;
      if (s->tail && !backward) last = from;
    }
  if (!s->tail)
    {
      if (!backward)
        {
          /* Tabbing in from before: the first visible item with key views. */
          for (NSInteger i = first; i <= last && i < n; i++)
            if ([self focusItemAtIndex: i last: NO]) return;
          [w selectKeyViewFollowingView: _tail];
        }
      else
        {
          for (NSInteger i = first - 1; i >= 0; i--)
            if ([self focusItemAtIndex: i last: YES]) return;
          [w selectKeyViewPrecedingView: _head];
        }
    }
  else
    {
      if (!backward)
        {
          for (NSInteger i = last + 1; i < n; i++)
            if ([self focusItemAtIndex: i last: NO]) return;
          [w selectKeyViewFollowingView: _tail];
        }
      else
        {
          /* Shift-Tabbing in from after: the last visible item. */
          for (NSInteger i = last; i >= first && i >= 0; i--)
            if ([self focusItemAtIndex: i last: YES]) return;
          [w selectKeyViewPrecedingView: _head];
        }
    }
}

/* ---- Scrolling ---- */

- (void)scrollToItemAtIndex:(NSInteger)index position:(TRVirtualScrollPosition)position
{
  if (_needsReload) [self syncCount];
  if (index < 0 || index >= _layout.itemCount) return;
  NSSize cs = [self contentSize];
  _layout.width = cs.width;
  /* Twice: the first pass measures what comes on screen. */
  for (int pass = 0; pass < 2; pass++)
    {
      NSRect f = [self rectOfItem: index];
      CGFloat cur = [[self contentView] bounds].origin.y, y = cur;
      switch (position)
        {
        case TRVirtualScrollTop: y = NSMinY(f); break;
        case TRVirtualScrollBottom: y = NSMaxY(f) - cs.height; break;
        case TRVirtualScrollCenter: y = NSMidY(f) - cs.height / 2; break;
        default:
          if (NSMinY(f) < cur) y = NSMinY(f);
          else if (NSMaxY(f) > cur + cs.height) y = MIN(NSMinY(f), NSMaxY(f) - cs.height);
        }
      y = MAX(0, MIN(y, _layout.contentHeight - cs.height));
      [_doc setFrameSize: NSMakeSize(cs.width, MAX(_layout.contentHeight, cs.height))];
      [[self contentView] scrollToPoint: NSMakePoint(0, y)];
      _updating = YES;
      [self reflectScrolledClipView: [self contentView]];
      _updating = NO;
      [self updateWithAnchor: (TRVirtualAnchor){ NSNotFound, 0 } use: NO];
    }
}

- (void)reflectScrolledClipView:(NSClipView *)clip
{
  [super reflectScrolledClipView: clip];
  if (!_updating && clip == [self contentView]) [self updateVirtualContent];
}

/* A resize keeps the item at the top of the viewport where it was (the
   anchor is taken before the size changes). */
- (void)resizeWith:(void (^)(void))change
{
  CGFloat offset = [[self contentView] bounds].origin.y;
  BOOL anchored = !_updating && offset > 0.5 && _layout.itemCount > 0;
  TRVirtualAnchor a = anchored ? [_layout anchorForOffset: offset] : (TRVirtualAnchor){ NSNotFound, 0 };
  change();
  if (_needsReload) [self syncCount];
  [self updateWithAnchor: a use: anchored];
}

/* GNUstep's -setFrame: does not go through -setFrameSize:, so both. */
- (void)setFrameSize:(NSSize)size
{
  [self resizeWith: ^{ [super setFrameSize: size]; }];
}

- (void)setFrame:(NSRect)frame
{
  [self resizeWith: ^{ [super setFrame: frame]; }];
}

/* ---- Queries ---- */

- (NSView *)viewForItemAtIndex:(NSInteger)index { return _realized[@(index)]; }

- (NSInteger)indexOfItemView:(NSView *)view
{
  for (NSNumber *k in _realized)
    if (view == _realized[k] || [view isDescendantOf: _realized[k]]) return [k integerValue];
  return NSNotFound;
}

- (NSArray<NSView *> *)visibleItemViews
{
  NSMutableArray *out = [NSMutableArray array];
  for (NSUInteger i = _visible.location; i < NSMaxRange(_visible); i++)
    if (_realized[@(i)]) [out addObject: _realized[@(i)]];
  return out;
}

- (NSIndexSet *)realizedIndexes
{
  NSMutableIndexSet *s = [NSMutableIndexSet indexSet];
  for (NSNumber *k in _realized) [s addIndex: [k unsignedIntegerValue]];
  return s;
}

- (NSUInteger)pooledViewCount
{
  NSUInteger n = 0;
  for (NSString *k in _kinds) n += [_kinds[k]->pool count];
  return n;
}

@end
