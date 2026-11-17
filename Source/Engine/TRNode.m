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

- (BOOL)isHidden { return _hidden; }
- (void)setHidden:(BOOL)hidden
{
  if (_hidden == hidden) return;
  _hidden = hidden;
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

/* A root inset in px, or a % of the available size; else 0. */
static TRFloat TRRootInset(TRValue v, TRFloat ref)
{
  if (v.unit == TRUnitPoint) return v.value;
  if (v.unit == TRUnitPercent && !isnan(ref)) return v.value * ref / 100;
  return 0;
}

- (void)_layoutOnceWithAvailableSize:(TRSize)available direction:(TRDirection)direction
{
  TRDirection own = _style->_s.direction == TRDirectionInherit ? direction : _style->_s.direction;
  TRStyleStorage kwBuf;
  const TRStyleStorage *s = TRResolveSizeKeywords(self, TRStyleStorageForDirection(_style, own), &kwBuf,
                                                  available.width, available.height,
                                                  available.width, available.height, YES, own);
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
      /* An abspos root without both left and right shrinks to fit the
         space (CSS 2 10.3.7): its auto width is fit-content, not stretch. */
      if (s->position == TRPositionAbsolute
          && (s->inset[TREdgeLeft].unit == TRUnitAuto || s->inset[TREdgeRight].unit == TRUnitAuto))
        wm = TRMeasureModeAtMost;
      else if (s->position == TRPositionAbsolute)
        aw = MAX(0, aw - TRRootInset(s->inset[TREdgeLeft], available.width) - TRRootInset(s->inset[TREdgeRight], available.width));
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
      /* ...and without both top and bottom its auto height is its content
         height (CSS 2 10.6.4). The space still resolves percentages. */
      if (s->position == TRPositionAbsolute
          && (s->inset[TREdgeTop].unit == TRUnitAuto || s->inset[TREdgeBottom].unit == TRUnitAuto))
        { ah = TRUndefined; hm = TRMeasureModeUndefined; }
      else if (s->position == TRPositionAbsolute)
        ah = MAX(0, ah - TRRootInset(s->inset[TREdgeTop], available.height) - TRRootInset(s->inset[TREdgeBottom], available.height));
    }
  /* min/max win over the root's own width/height (definite sizes only). */
  {
    TRFloat pbs[2] = {0, 0};
    for (int k = 0; k < 4; k++)
      {
        TRFloat v = 0;
        if (s->padding[k].unit == TRUnitPoint) v += s->padding[k].value;
        else if (s->padding[k].unit == TRUnitPercent && !isnan(available.width)) v += s->padding[k].value * available.width / 100;
        if (s->border[k].unit == TRUnitPoint) v += s->border[k].value;
        pbs[k % 2] += v;
      }
    TRFloat extra[2];
    for (int a = 0; a < 2; a++) extra[a] = s->boxSizing == TRBoxSizingContentBox ? pbs[a] : 0;
    if (wm == TRMeasureModeExactly && !isnan(aw))
      {
        if (s->maxWidth.unit == TRUnitPoint) aw = MIN(aw, s->maxWidth.value + extra[TREdgeLeft % 2]);
        if (s->minWidth.unit == TRUnitPoint) aw = MAX(aw, s->minWidth.value + extra[TREdgeLeft % 2]);
      }
    if (hm == TRMeasureModeExactly && !isnan(ah))
      {
        if (s->maxHeight.unit == TRUnitPoint) ah = MIN(ah, s->maxHeight.value + extra[TREdgeTop % 2]);
        if (s->minHeight.unit == TRUnitPoint) ah = MAX(ah, s->minHeight.value + extra[TREdgeTop % 2]);
      }
    /* A root with max-width/height and no available size: fit-content,
       bounded by the max as a border box. */
    /* A larger min-width/height wins over the max (CSS 2.1 10.4/10.7). */
    if (wm == TRMeasureModeUndefined && s->maxWidth.unit == TRUnitPoint)
      {
        aw = s->maxWidth.value;
        if (s->minWidth.unit == TRUnitPoint) aw = MAX(aw, s->minWidth.value);
        aw += extra[TREdgeLeft % 2]; wm = TRMeasureModeAtMost;
      }
    if (hm == TRMeasureModeUndefined && s->maxHeight.unit == TRUnitPoint)
      {
        ah = s->maxHeight.value;
        if (s->minHeight.unit == TRUnitPoint) ah = MAX(ah, s->minHeight.value);
        ah += extra[TREdgeTop % 2]; hm = TRMeasureModeAtMost;
      }
  }

  /* aspect-ratio on the root: a definite size in one axis (floored at
     padding + border and clamped) gives the other through the ratio,
     which applies to the content box (content-box) or the border box
     (border-box). An empty root with both sizes auto starts from its
     minimum height. min/max of the derived axis still apply. */
  if (!isnan(s->aspectRatio))
    {
      TRFloat ar = s->aspectRatio;
      TRFloat pb[2] = {0, 0};
      for (int k = 0; k < 4; k++)
        {
          TRFloat v = 0;
          if (s->padding[k].unit == TRUnitPoint) v += s->padding[k].value;
          else if (s->padding[k].unit == TRUnitPercent && !isnan(available.width)) v += s->padding[k].value * available.width / 100;
          if (s->border[k].unit == TRUnitPoint) v += s->border[k].value;
          pb[k % 2] += v;   /* [0] = vertical (top+bottom), [1] = horizontal */
        }
      TRFloat pbW = pb[1], pbH = pb[0];
      BOOL cb = s->boxSizing == TRBoxSizingContentBox;
      TRFloat cbx[2] = { cb ? pbW : 0, cb ? pbH : 0 };   /* min/max are content sizes in content-box */
      BOOL wDef = s->width.unit == TRUnitPoint || (s->width.unit == TRUnitPercent && !isnan(available.width));
      BOOL hDef = s->height.unit == TRUnitPoint || (s->height.unit == TRUnitPercent && !isnan(available.height));
      #define TR_CLAMP_W(x) ({ TRFloat _v = (x); \
        if (s->maxWidth.unit == TRUnitPoint) _v = MIN(_v, s->maxWidth.value + cbx[0]); \
        if (s->minWidth.unit == TRUnitPoint) _v = MAX(_v, s->minWidth.value + cbx[0]); MAX(_v, pbW); })
      #define TR_CLAMP_H(x) ({ TRFloat _v = (x); \
        if (s->maxHeight.unit == TRUnitPoint) _v = MIN(_v, s->maxHeight.value + cbx[1]); \
        if (s->minHeight.unit == TRUnitPoint) _v = MAX(_v, s->minHeight.value + cbx[1]); MAX(_v, pbH); })
      /* Border-box size in one axis to the other, through the ratio box. */
      BOOL rcb = cb || s->aspectRatioAuto;   /* the ratio box is the content box */
      #define TR_W_TO_H(w) (rcb ? ((w) - pbW) / ar + pbH : (w) / ar)
      #define TR_H_TO_W(h) (rcb ? ((h) - pbH) * ar + pbW : (h) * ar)
      BOOL empty = [_children count] == 0 && _measure == nil;
      if (wDef && !hDef)
        {
          aw = TR_CLAMP_W(aw);
          ah = TR_CLAMP_H(TR_W_TO_H(aw)); hm = TRMeasureModeExactly;
        }
      else if (hDef && !wDef)
        {
          ah = TR_CLAMP_H(ah);
          aw = TR_CLAMP_W(TR_H_TO_W(ah)); wm = TRMeasureModeExactly;
        }
      else if (!wDef && !hDef && empty)
        {
          TRFloat h0 = TR_CLAMP_H(pbH);
          aw = TR_CLAMP_W(TR_H_TO_W(h0));
          if (!isnan(available.width) && s->width.unit == TRUnitAuto) aw = MIN(aw, MAX(available.width, pbW));
          wm = TRMeasureModeExactly;
          ah = TR_CLAMP_H(TR_W_TO_H(aw)); hm = TRMeasureModeExactly;
        }
      else if (!hDef && wm == TRMeasureModeExactly && !isnan(aw))
        {
          /* An auto width that fills the available width is definite too.
             With min-height: auto the height is at least the content's
             (css-sizing-4 automatic minimum for aspect-ratio boxes). */
          aw = TR_CLAMP_W(aw);
          TRFloat h = TR_W_TO_H(aw);
          if (s->minHeight.unit == TRUnitAuto && s->overflow == TROverflowVisible)
            h = MAX(h, TRLayoutNode(self, aw, TRUndefined, TRMeasureModeExactly, TRMeasureModeUndefined,
                                    available.width, available.height, NO, own).height);
          ah = TR_CLAMP_H(h); hm = TRMeasureModeExactly;
        }
      #undef TR_CLAMP_W
      #undef TR_CLAMP_H
      #undef TR_W_TO_H
      #undef TR_H_TO_W
    }

  /* Size a fit-content root's width first, then lay it out at that exact
     width so its children's percentages resolve against it. (As in CSS,
     a shrink-to-fit width becomes definite; an auto height does not.) */
  if (wm != TRMeasureModeExactly)
    {
      TRSize sz = TRLayoutNode(self, aw, ah, wm, hm, available.width, available.height, NO, direction);
      aw = sz.width;
      wm = TRMeasureModeExactly;
    }
  _isLayoutRoot = YES;
  TRLayoutNode(self, aw, ah, wm, hm, available.width, available.height, YES, direction);
  _isLayoutRoot = NO;

  TRFloat x = s->margin[TREdgeLeft].unit == TRUnitPoint ? s->margin[TREdgeLeft].value : 0;
  TRFloat y = s->margin[TREdgeTop].unit == TRUnitPoint ? s->margin[TREdgeTop].value : 0;
  /* A positioned root is offset by its own left/top insets. */
  if (s->position != TRPositionStatic)
    {
      if (s->inset[TREdgeLeft].unit == TRUnitPoint) x += s->inset[TREdgeLeft].value;
      else if (s->inset[TREdgeLeft].unit == TRUnitPercent && !isnan(available.width))
        x += s->inset[TREdgeLeft].value * available.width / 100;
      if (s->inset[TREdgeTop].unit == TRUnitPoint) y += s->inset[TREdgeTop].value;
      else if (s->inset[TREdgeTop].unit == TRUnitPercent && !isnan(available.height))
        y += s->inset[TREdgeTop].value * available.height / 100;
    }
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
