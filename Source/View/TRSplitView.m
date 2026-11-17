/* TRSplitView.m - resizable panes with draggable dividers (<split>).

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRSplitView.h"

@interface TRSplitPane : NSObject
{
@public
  __weak NSView *view;
  CGFloat initial;     /* NAN: unset */
  CGFloat min, max;    /* 0 / CGFLOAT_MAX: unset */
  CGFloat grow;        /* flex-grow; -1: unset */
  CGFloat size;        /* current size along the split */
}
@end
@implementation TRSplitPane
@end

@interface TRSplitView ()
@end

@implementation TRSplitView
{
  TRSplitDirection _direction;
  NSMutableArray<TRSplitPane *> *_panes;
  BOOL _sized;          /* sizes chosen by a drag or in code: kept from now on */
  BOOL _applying;       /* setting pane frames ourselves */
  BOOL _tracking;       /* the user is dragging a divider */
}

- (instancetype)initWithDirection:(TRSplitDirection)direction
{
  if ((self = [super initWithFrame: NSMakeRect(0, 0, 100, 100)]) != nil)
    {
      _direction = direction;
      _panes = [NSMutableArray array];
      [self setVertical: direction == TRSplitDirectionRow];
      [self setDividerStyle: NSSplitViewDividerStyleThin];
      [super setDelegate: self];
    }
  return self;
}

- (instancetype)initWithFrame:(NSRect)frame
{
  self = [self initWithDirection: TRSplitDirectionRow];
  [self setFrame: frame];
  return self;
}

- (TRSplitDirection)direction { return _direction; }

/* ---- Panes ---- */

- (TRSplitPane *)infoForPane:(NSView *)pane
{
  for (TRSplitPane *p in _panes)
    if (p->view == pane) return p;
  return nil;
}

- (void)addPane:(NSView *)pane
{
  TRSplitPane *p = [TRSplitPane new];
  p->view = pane;
  p->initial = NAN;
  p->min = 0;
  p->max = CGFLOAT_MAX;
  p->grow = -1;
  p->size = 0;
  [_panes addObject: p];
  [self addSubview: pane];
  [pane setAutoresizingMask: NSViewNotSizable];
  _sized = NO;
  [self applySizes];
}

- (NSArray<NSView *> *)panes
{
  NSMutableArray *a = [NSMutableArray array];
  for (TRSplitPane *p in _panes)
    if (p->view) [a addObject: p->view];
  return a;
}

- (void)willRemoveSubview:(NSView *)subview
{
  TRSplitPane *p = [self infoForPane: subview];
  if (p) [_panes removeObject: p];
  [super willRemoveSubview: subview];
}

- (void)setInitialSize:(CGFloat)size forPane:(NSView *)pane
{
  TRSplitPane *p = [self infoForPane: pane];
  if (p == nil) return;
  p->initial = size;
  _sized = NO;
  [self applySizes];
}

- (void)setMinimumSize:(CGFloat)min maximumSize:(CGFloat)max forPane:(NSView *)pane
{
  TRSplitPane *p = [self infoForPane: pane];
  if (p == nil) return;
  p->min = MAX(0, min);
  p->max = max > 0 ? max : CGFLOAT_MAX;
  [self applySizes];
}

- (void)setGrowWeight:(CGFloat)weight forPane:(NSView *)pane
{
  TRSplitPane *p = [self infoForPane: pane];
  if (p) p->grow = weight;
}

static CGFloat TRPoints(TRValue v, CGFloat unset)
{
  return v.unit == TRUnitPoint ? v.value : unset;
}

- (void)setSizingFromStyle:(TRStyle *)st forPane:(NSView *)pane
{
  TRSplitPane *p = [self infoForPane: pane];
  if (p == nil || st == nil) return;
  BOOL row = (_direction == TRSplitDirectionRow);
  p->initial = TRPoints(row ? st.width : st.height, NAN);
  if (isnan(p->initial)) p->initial = TRPoints(st.flexBasis, NAN);
  p->min = MAX(0, TRPoints(row ? st.minWidth : st.minHeight, 0));
  p->max = TRPoints(row ? st.maxWidth : st.maxHeight, CGFLOAT_MAX);
  if (p->max <= 0) p->max = CGFLOAT_MAX;
  if (st.flexGrow > 0) p->grow = st.flexGrow;
  _sized = NO;
  [self applySizes];
}

/* ---- Sizing ---- */

- (CGFloat)length
{
  NSSize s = [self bounds].size;
  return _direction == TRSplitDirectionRow ? s.width : s.height;
}

- (CGFloat)available
{
  NSUInteger n = [_panes count];
  CGFloat d = n > 1 ? [self dividerThickness] * (n - 1) : 0;
  return MAX(0, [self length] - d);
}

static CGFloat TRClampPane(TRSplitPane *p, CGFloat s)
{
  if (s > p->max) s = p->max;
  if (s < p->min) s = p->min;
  return s;
}

/* Gives `delta` (positive or negative) to the panes, by grow weight
   (the last pane when none has one), within their limits; what a pane
   can't take goes to the others. */
- (void)distribute:(CGFloat)delta
{
  NSUInteger n = [_panes count];
  if (n == 0) return;
  BOOL anyGrow = NO;
  for (TRSplitPane *p in _panes) if (p->grow > 0) anyGrow = YES;
  NSMutableArray *open = [NSMutableArray array];
  for (NSUInteger i = 0; i < n; i++)
    {
      TRSplitPane *p = _panes[i];
      if (anyGrow ? p->grow > 0 : i == n - 1) [open addObject: p];
    }
  for (int pass = 0; pass < 3 && fabs(delta) >= 0.5; pass++)
    {
      if ([open count] == 0)
        {
          /* The preferred panes are at their limits: the rest, last first. */
          for (NSInteger i = (NSInteger)n - 1; i >= 0; i--) [open addObject: _panes[i]];
        }
      CGFloat total = 0;
      for (TRSplitPane *p in open) total += anyGrow && p->grow > 0 ? p->grow : 1;
      CGFloat left = delta;
      NSMutableArray *still = [NSMutableArray array];
      for (TRSplitPane *p in open)
        {
          CGFloat w = (anyGrow && p->grow > 0 ? p->grow : 1) / total;
          CGFloat want = p->size + delta * w;
          CGFloat got = TRClampPane(p, want);
          left -= got - p->size;
          p->size = got;
          if (got == want) [still addObject: p];
        }
      delta = left;
      open = still;
    }
}

/* Sizes from the preferences: saved ones, else each pane's initial size,
   the rest shared out among the panes without one. Until a drag or
   -setDividerPositions: picks sizes, every layout starts from here, so a
   split that is small for a moment (before its first real layout)
   doesn't squeeze its panes for good. */
- (void)assignInitialSizes
{
  CGFloat avail = [self available];
  NSUInteger n = [_panes count];
  NSArray *saved = nil;
  if ([_autosave length])
    saved = [[NSUserDefaults standardUserDefaults] arrayForKey:
              [@"TRSplitView Panes " stringByAppendingString: _autosave]];
  if ([saved count] == n)
    {
      for (NSUInteger i = 0; i < n; i++)
        _panes[i]->size = TRClampPane(_panes[i], [saved[i] doubleValue]);
    }
  else
    {
      CGFloat used = 0;
      NSUInteger open = 0;
      for (TRSplitPane *p in _panes)
        {
          if (!isnan(p->initial)) { p->size = TRClampPane(p, p->initial); used += p->size; }
          else { p->size = 0; open++; }
        }
      if (open)
        {
          CGFloat share = MAX(0, avail - used) / open;
          for (TRSplitPane *p in _panes)
            if (isnan(p->initial)) p->size = TRClampPane(p, share);
        }
    }
  CGFloat sum = 0;
  for (TRSplitPane *p in _panes) sum += p->size;
  [self distribute: avail - sum];
}

/* Sets the pane frames from the sizes (fitting them to the split first). */
- (void)applySizes
{
  NSUInteger n = [_panes count];
  if (n == 0 || [self length] <= 0) return;
  if (!_sized) [self assignInitialSizes];
  else
    {
      CGFloat sum = 0;
      for (TRSplitPane *p in _panes) sum += p->size;
      [self distribute: [self available] - sum];
    }
  /* Container queries in a pane test the container outside the split. */
  NSView *sv = [self superview];
  TRNode *cq = [sv isKindOfClass: [TRBoxView class]] ? [(TRBoxView *)sv nodeForSubview: self] : nil;
  for (TRSplitPane *p in _panes)
    if ([p->view isKindOfClass: [TRBoxView class]]) ((TRBoxView *)p->view).node.containerQueryParent = cq;
  NSSize s = [self bounds].size;
  CGFloat pos = 0, thick = [self dividerThickness];
  _applying = YES;
  for (NSUInteger i = 0; i < n; i++)
    {
      TRSplitPane *p = _panes[i];
      CGFloat sz = round(p->size);
      if (i == n - 1) sz = MAX(0, [self length] - pos);   /* absorb rounding */
      NSRect f = _direction == TRSplitDirectionRow ? NSMakeRect(pos, 0, sz, s.height)
                                                   : NSMakeRect(0, pos, s.width, sz);
      if (!NSEqualRects([p->view frame], f)) [p->view setFrame: f];
      pos += sz + thick;
    }
  _applying = NO;
  [self setNeedsDisplay: YES];
}

/* Reads the sizes back from the pane frames (after AppKit moved a divider). */
- (void)syncSizesFromFrames
{
  for (TRSplitPane *p in _panes)
    {
      NSRect f = [p->view frame];
      p->size = _direction == TRSplitDirectionRow ? NSWidth(f) : NSHeight(f);
    }
}

- (void)save
{
  if (![_autosave length]) return;
  NSMutableArray *a = [NSMutableArray array];
  for (TRSplitPane *p in _panes) [a addObject: @(round(p->size))];
  [[NSUserDefaults standardUserDefaults] setObject: a forKey:
    [@"TRSplitView Panes " stringByAppendingString: _autosave]];
}

- (NSArray<NSNumber *> *)dividerPositions
{
  NSMutableArray *a = [NSMutableArray array];
  CGFloat pos = 0, thick = [self dividerThickness];
  for (NSUInteger i = 0; i + 1 < [_panes count]; i++)
    {
      pos += _panes[i]->size;
      [a addObject: @(round(pos))];
      pos += thick;
    }
  return a;
}

- (void)setDividerPositions:(NSArray<NSNumber *> *)positions
{
  NSUInteger n = [_panes count];
  if (n < 2) return;
  if (!_sized && [self length] > 0) [self assignInitialSizes];
  CGFloat thick = [self dividerThickness], start = 0;
  for (NSUInteger i = 0; i + 1 < n && i < [positions count]; i++)
    {
      CGFloat want = [positions[i] doubleValue] - start;
      _panes[i]->size = TRClampPane(_panes[i], want);
      start += _panes[i]->size + thick;
    }
  /* The last pane takes the rest, within its limits (applySizes fits). */
  CGFloat used = 0;
  for (NSUInteger i = 0; i + 1 < n; i++) used += _panes[i]->size;
  _panes[n - 1]->size = MAX(0, [self available] - used);
  _sized = YES;
  [self applySizes];
  [self save];
}

/* NSSplitView's own call goes through the same clamping and saving. */
- (void)setPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)index
{
  NSMutableArray *a = [[self dividerPositions] mutableCopy];
  if (index < 0 || index >= (NSInteger)[a count]) return;
  a[index] = @(position);
  [self setDividerPositions: a];
}

- (void)setAutosave:(NSString *)name
{
  _autosave = [name copy];
  _sized = NO;
  [self applySizes];
}

/* ---- NSSplitView ---- */

- (void)setFrameSize:(NSSize)size
{
  [super setFrameSize: size];
  [self applySizes];
}

- (void)setFrame:(NSRect)frame
{
  [super setFrame: frame];
  [self applySizes];
}


- (void)splitView:(NSSplitView *)sender resizeSubviewsWithOldSize:(NSSize)oldSize
{
  [self applySizes];
}

- (void)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat *)min
    maxCoordinate:(CGFloat *)max ofSubviewAt:(NSInteger)offset
{
  CGFloat lo = [self splitView: sender constrainMinCoordinate: *min ofSubviewAt: offset];
  CGFloat hi = [self splitView: sender constrainMaxCoordinate: *max ofSubviewAt: offset];
  if (lo > *min) *min = lo;
  if (hi < *max) *max = hi;
}

/* The leading edge of pane i and the trailing edge of pane i + 1. */
- (void)edgesAround:(NSInteger)i start:(CGFloat *)start end:(CGFloat *)end
{
  NSRect a = [_panes[i]->view frame], b = [_panes[i + 1]->view frame];
  BOOL row = (_direction == TRSplitDirectionRow);
  *start = row ? NSMinX(a) : NSMinY(a);
  *end = row ? NSMaxX(b) : NSMaxY(b);
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposed
         ofSubviewAt:(NSInteger)i
{
  if (i < 0 || i + 1 >= (NSInteger)[_panes count]) return proposed;
  CGFloat start, end, thick = [self dividerThickness];
  [self edgesAround: i start: &start end: &end];
  CGFloat lo = start + _panes[i]->min;
  if (_panes[i + 1]->max < CGFLOAT_MAX) lo = MAX(lo, end - _panes[i + 1]->max - thick);
  return MAX(proposed, lo);
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposed
         ofSubviewAt:(NSInteger)i
{
  if (i < 0 || i + 1 >= (NSInteger)[_panes count]) return proposed;
  CGFloat start, end, thick = [self dividerThickness];
  [self edgesAround: i start: &start end: &end];
  CGFloat hi = end - _panes[i + 1]->min - thick;
  if (_panes[i]->max < CGFLOAT_MAX) hi = MIN(hi, start + _panes[i]->max);
  return MIN(proposed, hi);
}

- (CGFloat)splitView:(NSSplitView *)sender constrainSplitPosition:(CGFloat)proposed
         ofSubviewAt:(NSInteger)i
{
  CGFloat lo = [self splitView: sender constrainMinCoordinate: proposed ofSubviewAt: i];
  return [self splitView: sender constrainMaxCoordinate: lo ofSubviewAt: i];
}

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview
{
  return NO;
}

- (void)splitViewDidResizeSubviews:(NSNotification *)note
{
  if (!_applying && _tracking) [self syncSizesFromFrames];
}

- (void)mouseDown:(NSEvent *)event
{
  /* NSSplitView tracks the drag inside -mouseDown: on both platforms. */
  _tracking = YES;
  [super mouseDown: event];
  _tracking = NO;
  [self syncSizesFromFrames];
  _sized = YES;
  [self applySizes];   /* whole points, and the limits, whatever AppKit did */
  [self save];
  if (_action && _target)
    [NSApp sendAction: _action to: _target from: self];
}

/* ---- Trellis ---- */

- (NSArray<NSView *> *)trellisKeyViewSubtrees
{
  return [self panes];
}

static NSSize TRPaneNaturalSize(NSView *v, CGFloat width)
{
  if ([v isKindOfClass: [TRBoxView class]])
    {
      TRBoxView *b = (TRBoxView *)v;
      if (width >= CGFLOAT_MAX / 2)
        {
          [b.node layoutWithAvailableSize: TRSizeMake(NAN, NAN)];
          TRRect f = b.node.layoutFrame;
          NSSize s = NSMakeSize(f.width, f.height);
          [b layoutTrellis];   /* back to its real size */
          return s;
        }
      return NSMakeSize(width, [b heightForWidth: width]);
    }
  if ([v conformsToProtocol: @protocol(TRSizeForWidth)])
    return [(id<TRSizeForWidth>)v trellisSizeForWidth: width];
  BOOL definite = width < CGFLOAT_MAX / 2;
  TRSize s = TRMeasureView(v, TRSizeMake(definite ? width : NAN, NAN),
                           definite ? TRMeasureModeExactly : TRMeasureModeUndefined, TRMeasureModeUndefined);
  return NSMakeSize(definite ? width : s.width, s.height);
}

/* What the split needs inside its parent box: along the split, the panes'
   starting (or minimum, or natural) sizes and the dividers; across it,
   the tallest (widest) pane. */
- (NSSize)trellisSizeForWidth:(CGFloat)width
{
  NSUInteger n = [_panes count];
  CGFloat thick = n > 1 ? [self dividerThickness] * (n - 1) : 0;
  BOOL row = (_direction == TRSplitDirectionRow);
  CGFloat along = thick, across = 0;
  for (TRSplitPane *p in _panes)
    {
      CGFloat sz = !isnan(p->initial) ? p->initial : p->min;
      if (row)
        {
          NSSize nat = TRPaneNaturalSize(p->view, sz > 0 ? sz : CGFLOAT_MAX);
          if (sz <= 0) sz = nat.width;
          along += sz;
          across = MAX(across, nat.height);
        }
      else
        {
          NSSize nat = TRPaneNaturalSize(p->view, width);
          if (sz <= 0) sz = nat.height;
          along += sz;
          across = MAX(across, width < CGFLOAT_MAX / 2 ? width : nat.width);
        }
    }
  return row ? NSMakeSize(width < CGFLOAT_MAX / 2 ? width : along, across)
             : NSMakeSize(across, along);
}

@end
