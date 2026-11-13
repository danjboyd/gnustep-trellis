/* TRNode.m - a box in a Trellis layout tree.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRNode+Internal.h"

@implementation TRNode

@synthesize identifier = _identifier;
@synthesize context = _context;
@synthesize pixelScale = _pixelScale;

+ (instancetype)node
{
  return [[self alloc] init];
}

+ (instancetype)nodeWithStyle:(id)style
{
  return [self nodeWithStyle: style children: nil];
}

+ (instancetype)nodeWithStyle:(id)style children:(NSArray<TRNode *> *)children
{
  TRNode *n = [[self alloc] init];
  NSError *err = nil;
  BOOL ok = YES;
  if ([style isKindOfClass: [NSString class]])
    ok = [n->_style applyDeclarations: style error: &err];
  else if ([style isKindOfClass: [NSDictionary class]])
    ok = [n->_style applyDictionary: style error: &err];
  else if ([style isKindOfClass: [TRStyle class]])
    n.style = style;
  else if (style != nil)
    {
      ok = NO;
      err = [NSError errorWithDomain: TRStyleErrorDomain code: 2
                            userInfo: @{NSLocalizedDescriptionKey: @"style must be an NSString, NSDictionary or TRStyle"}];
    }
  if (!ok)
    [NSException raise: NSInvalidArgumentException
                format: @"Trellis: bad style: %@", [err localizedDescription]];
  for (TRNode *c in children) [n addChild: c];
  return n;
}

- (instancetype)init
{
  if ((self = [super init]) != nil)
    {
      _style = [[TRStyle alloc] init];
      _style.owner = self;
      _children = [NSMutableArray array];
      _dirty = YES;
      _pixelScale = 1.0;
      _lineIndex = -1;
    }
  return self;
}

- (TRStyle *)style
{
  return _style;
}

- (void)setStyle:(TRStyle *)style
{
  _style = [style copy];
  _style.owner = self;
  if (_conditions != nil)
    {
      _baseStyle = [style copy];
      _matchedMask = 0;
    }
  [self markDirty];
}

- (NSArray<TRNode *> *)children
{
  return [_children copy];
}

- (TRNode *)parent
{
  return _parent;
}

- (void)addChild:(TRNode *)child
{
  [self insertChild: child atIndex: [_children count]];
}

- (void)insertChild:(TRNode *)child atIndex:(NSUInteger)index
{
  NSAssert(child != self, @"a node cannot contain itself");
  TRNode *old = child->_parent;
  if (old != nil) [old removeChild: child];
  [_children insertObject: child atIndex: index];
  child->_parent = self;
  [self markDirty];
}

- (void)removeChild:(TRNode *)child
{
  if (child->_parent != self) return;
  [_children removeObjectIdenticalTo: child];
  child->_parent = nil;
  [self markDirty];
}

- (void)removeAllChildren
{
  for (TRNode *c in _children) c->_parent = nil;
  [_children removeAllObjects];
  [self markDirty];
}

- (TRMeasureBlock)measureBlock { return _measure; }
- (void)setMeasureBlock:(TRMeasureBlock)b { _measure = [b copy]; [self markDirty]; }
- (TRBaselineBlock)baselineBlock { return _baselineFn; }
- (void)setBaselineBlock:(TRBaselineBlock)b { _baselineFn = [b copy]; [self markDirty]; }

- (void)markDirty
{
  for (TRNode *n = self; n != nil; n = n->_parent)
    {
      n->_dirty = YES;
      n->_cacheCount = 0;
      n->_cacheNext = 0;
      n->_hasPerformEntry = NO;
    }
}

- (BOOL)isDirty
{
  return _dirty;
}

static void TRClearDirty(TRNode *n)
{
  n->_dirty = NO;
  for (TRNode *c in n->_children) TRClearDirty(c);
}

- (void)layoutWithAvailableSize:(TRSize)available
{
  [self layoutWithAvailableSize: available direction: TRDirectionLTR];
}

- (void)layoutWithAvailableSize:(TRSize)available direction:(TRDirection)direction
{
  /* Container queries can change styles, which changes sizes: iterate
     until stable (in practice one or two passes). */
  for (int pass = 0; pass < 4; pass++)
    {
      [self _layoutOnceWithAvailableSize: available direction: direction];
      if (!TRApplyContainerQueries(self)) break;
    }
  TRRoundTree(self, 0, 0, _pixelScale);
  TRClearDirty(self);
}

- (void)_layoutOnceWithAvailableSize:(TRSize)available direction:(TRDirection)direction
{
  const TRStyleStorage *s = &_style->_s;
  TRFloat aw = available.width, ah = available.height;
  TRMeasureMode wm = isnan(aw) ? TRMeasureModeUndefined : TRMeasureModeExactly;
  TRMeasureMode hm = isnan(ah) ? TRMeasureModeUndefined : TRMeasureModeExactly;

  /* The root's own definite size wins over the available size. Margins
     of the root are honoured by offsetting it. */
  if (s->width.unit == TRUnitPoint || (s->width.unit == TRUnitPercent && !isnan(aw)))
    {
      TRFloat pb = 0;
      for (int k = 0; k < 4; k += 2)
        {
          if (s->padding[k].unit == TRUnitPoint) pb += s->padding[k].value;
          else if (s->padding[k].unit == TRUnitPercent && !isnan(aw)) pb += s->padding[k].value * aw / 100;
          if (s->border[k].unit == TRUnitPoint) pb += s->border[k].value;
        }
      TRFloat w = s->width.unit == TRUnitPoint ? s->width.value : s->width.value * aw / 100;
      aw = s->boxSizing == TRBoxSizingContentBox ? w + pb : MAX(w, pb);
      wm = TRMeasureModeExactly;
    }
  else if (!isnan(aw))
    {
      TRFloat ml = s->margin[TREdgeLeft].unit == TRUnitPoint ? s->margin[TREdgeLeft].value : 0;
      TRFloat mr = s->margin[TREdgeRight].unit == TRUnitPoint ? s->margin[TREdgeRight].value : 0;
      aw = MAX(0, aw - ml - mr);
    }
  if (s->height.unit == TRUnitPoint || (s->height.unit == TRUnitPercent && !isnan(ah)))
    {
      TRFloat pb = 0;
      for (int k = 1; k < 4; k += 2)
        {
          if (s->padding[k].unit == TRUnitPoint) pb += s->padding[k].value;
          else if (s->padding[k].unit == TRUnitPercent && !isnan(available.width)) pb += s->padding[k].value * available.width / 100;
          if (s->border[k].unit == TRUnitPoint) pb += s->border[k].value;
        }
      TRFloat h = s->height.unit == TRUnitPoint ? s->height.value : s->height.value * ah / 100;
      ah = s->boxSizing == TRBoxSizingContentBox ? h + pb : MAX(h, pb);
      hm = TRMeasureModeExactly;
    }
  else if (!isnan(ah))
    {
      TRFloat mt = s->margin[TREdgeTop].unit == TRUnitPoint ? s->margin[TREdgeTop].value : 0;
      TRFloat mb = s->margin[TREdgeBottom].unit == TRUnitPoint ? s->margin[TREdgeBottom].value : 0;
      ah = MAX(0, ah - mt - mb);
    }
  /* A root with max-width/height and no available size: fit-content. */
  if (wm == TRMeasureModeUndefined && s->maxWidth.unit == TRUnitPoint)
    { aw = s->maxWidth.value; wm = TRMeasureModeAtMost; }
  if (hm == TRMeasureModeUndefined && s->maxHeight.unit == TRUnitPoint)
    { ah = s->maxHeight.value; hm = TRMeasureModeAtMost; }

  TRLayoutNode(self, aw, ah, wm, hm, available.width, available.height, YES, direction);

  TRFloat x = s->margin[TREdgeLeft].unit == TRUnitPoint ? s->margin[TREdgeLeft].value : 0;
  TRFloat y = s->margin[TREdgeTop].unit == TRUnitPoint ? s->margin[TREdgeTop].value : 0;
  _rawFrame.x = x;
  _rawFrame.y = y;
}

- (TRRect)layoutFrame { return _frame; }
- (TRDirection)layoutDirection { return _ldir; }
- (TRSize)contentSize { return _contentSize; }
- (TRFloat)layoutPaddingForEdge:(TREdge)e { return _lpad[e]; }
- (TRFloat)layoutBorderForEdge:(TREdge)e { return _lborder[e]; }
- (TRFloat)layoutMarginForEdge:(TREdge)e { return _lmargin[e]; }

- (TRRect)absoluteFrame
{
  TRRect r = _frame;
  for (TRNode *p = _parent; p != nil; p = p->_parent)
    {
      r.x += p->_frame.x;
      r.y += p->_frame.y;
    }
  return r;
}

- (TRFloat)layoutBaseline
{
  return TRComputeBaseline(self);
}

- (BOOL)hasOverflow
{
  if (_measure == nil || [_children count] > 0) return NO;
  TRFloat iw = _rawFrame.width - _lpad[TREdgeLeft] - _lpad[TREdgeRight]
             - _lborder[TREdgeLeft] - _lborder[TREdgeRight];
  TRFloat ih = _rawFrame.height - _lpad[TREdgeTop] - _lpad[TREdgeBottom]
             - _lborder[TREdgeTop] - _lborder[TREdgeBottom];
  TRSize m = _measure(TRSizeMake(iw, TRUndefined), TRMeasureModeAtMost, TRMeasureModeUndefined);
  return m.width > iw + 0.5 || m.height > ih + 0.5;
}

- (NSDictionary *)frameDump
{
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  if (_identifier) d[@"id"] = _identifier;
  d[@"x"] = @(_frame.x);
  d[@"y"] = @(_frame.y);
  d[@"width"] = @(_frame.width);
  d[@"height"] = @(_frame.height);
  NSString *decl = [_style declarationString];
  if ([decl length]) d[@"style"] = decl;
  if ([_children count])
    {
      NSMutableArray *kids = [NSMutableArray array];
      for (TRNode *c in _children) [kids addObject: [c frameDump]];
      d[@"children"] = kids;
    }
  return d;
}

- (NSString *)description
{
  return [NSString stringWithFormat: @"<TRNode %@ {%g,%g %gx%g}>",
           _identifier ? _identifier : @"", _frame.x, _frame.y, _frame.width, _frame.height];
}

@end
