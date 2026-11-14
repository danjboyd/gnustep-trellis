/* TRLayout.m - the Trellis Flexbox layout algorithm.

   An implementation of CSS Flexible Box Layout Level 1 (section 9, "Flex
   Layout Algorithm") over TRNode trees, with Yoga's measure-mode model for
   intrinsic sizing. Foundation-only.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRNode+Internal.h"
#include <stdlib.h>

TRSize TRLayoutGrid(TRNode *node, const TRStyleStorage *s, TRFloat pad[4], TRFloat border[4],
                    TRFloat aw, TRFloat ah, TRMeasureMode wm, TRMeasureMode hm,
                    TRFloat ow, TRFloat oh, BOOL perform, TRDirection dir);

/* ------------------------------------------------------------------ */
#pragma mark Small helpers

static inline TRFloat TRMax(TRFloat a, TRFloat b) { return a > b ? a : b; }
static inline TRFloat TRMin(TRFloat a, TRFloat b) { return a < b ? a : b; }
static inline TRFloat TRDefault(TRFloat v, TRFloat d) { return isnan(v) ? d : v; }

/* Resolves a length against a reference length; NAN for auto, none, or a
   percentage of an indefinite reference. */
static inline TRFloat TRResolve(TRValue v, TRFloat ref)
{
  switch (v.unit)
    {
      case TRUnitPoint: return v.value;
      case TRUnitPercent: return isnan(ref) ? TRUndefined : v.value * ref / 100.0;
      default: return TRUndefined;
    }
}

static inline BOOL TRFloatsEqual(TRFloat a, TRFloat b)
{
  if (isnan(a)) return isnan(b);
  if (isnan(b)) return NO;
  return fabs(a - b) < 0.0001;
}

/* Clamp with CSS semantics: max is applied first, then min wins. */
static inline TRFloat TRClamp(TRFloat v, TRFloat lo, TRFloat hi)
{
  if (!isnan(hi) && v > hi) v = hi;
  if (!isnan(lo) && v < lo) v = lo;
  return v;
}

/* Edge helpers. For an axis (row = horizontal), the physical edge at the
   logical start, given whether that axis is reversed. */
static inline TREdge TRLeadingEdge(BOOL horizontal, BOOL reversed)
{
  if (horizontal) return reversed ? TREdgeRight : TREdgeLeft;
  return reversed ? TREdgeBottom : TREdgeTop;
}
static inline TREdge TRTrailingEdge(BOOL horizontal, BOOL reversed)
{
  if (horizontal) return reversed ? TREdgeLeft : TREdgeRight;
  return reversed ? TREdgeTop : TREdgeBottom;
}

typedef struct {
  TRFloat pad[4];
  TRFloat border[4];
} TREdges;

static TREdges TRResolveEdges(const TRStyleStorage *s, TRFloat refWidth)
{
  TREdges e;
  for (int i = 0; i < 4; i++)
    {
      /* Percentages of padding resolve against the containing block's
         inline size for all four edges (CSS 2.1 8.4). */
      e.pad[i] = TRMax(0, TRDefault(TRResolve(s->padding[i], refWidth), 0));
      e.border[i] = TRMax(0, TRDefault(TRResolve(s->border[i], TRUndefined), 0));
    }
  return e;
}

static inline TRFloat TRPBHorizontal(const TREdges *e)
{ return e->pad[TREdgeLeft] + e->pad[TREdgeRight] + e->border[TREdgeLeft] + e->border[TREdgeRight]; }
static inline TRFloat TRPBVertical(const TREdges *e)
{ return e->pad[TREdgeTop] + e->pad[TREdgeBottom] + e->border[TREdgeTop] + e->border[TREdgeBottom]; }

/* A size property converted to a border-box size, honouring box-sizing.
   NAN if it does not resolve. */
static TRFloat TRBoxSize(const TRStyleStorage *s, TRValue v, TRFloat ref, TRFloat pb)
{
  TRFloat r = TRResolve(v, ref);
  if (isnan(r)) return TRUndefined;
  if (s->boxSizing == TRBoxSizingContentBox) return TRMax(0, r) + pb;
  return TRMax(r, pb);
}

static inline TRAlign TRResolveAlignSelf(const TRStyleStorage *item, const TRStyleStorage *container)
{
  TRAlign a = item->alignSelf;
  if (a == TRAlignAuto) a = container->alignItems;
  if (a == TRAlignNormal) a = TRAlignStretch;
  /* Last-baseline sharing is not implemented: use its fallback, 'end'. */
  if (a == TRAlignLastBaseline) a = TRAlignEnd;
  return a;
}

static inline BOOL TRIsInFlow(TRNode *child)
{
  const TRStyleStorage *s = &child->_style->_s;
  return s->display != TRDisplayNone && s->position != TRPositionAbsolute;
}

/* ------------------------------------------------------------------ */
#pragma mark Cache

/* The containing block size (ow/oh) only affects a node's own layout
   through percentages in its padding or min/max sizes; when it has none,
   it is left out of the cache key, so e.g. max-content measurements stay
   cached while a window is resized. */
static BOOL TRUsesOwnerSize(const TRStyleStorage *s)
{
  for (int i = 0; i < 4; i++)
    if (s->padding[i].unit == TRUnitPercent) return YES;
  return s->minWidth.unit == TRUnitPercent || s->maxWidth.unit == TRUnitPercent
      || s->minHeight.unit == TRUnitPercent || s->maxHeight.unit == TRUnitPercent;
}

static BOOL TRCacheMatch(const TRCacheEntry *e, TRFloat aw, TRFloat ah,
                         TRMeasureMode wm, TRMeasureMode hm,
                         TRFloat ow, TRFloat oh, TRDirection dir, BOOL ownerMatters)
{
  if (e->wm != wm || e->hm != hm || e->dir != dir) return NO;
  if (wm != TRMeasureModeUndefined && !TRFloatsEqual(e->aw, aw)) return NO;
  if (hm != TRMeasureModeUndefined && !TRFloatsEqual(e->ah, ah)) return NO;
  if (ownerMatters && (!TRFloatsEqual(e->ow, ow) || !TRFloatsEqual(e->oh, oh))) return NO;
  return YES;
}

static void TRCacheStore(TRNode *n, TRFloat aw, TRFloat ah,
                         TRMeasureMode wm, TRMeasureMode hm,
                         TRFloat ow, TRFloat oh, TRDirection dir, TRSize result)
{
  TRCacheEntry *e = &n->_cache[n->_cacheNext];
  e->aw = aw; e->ah = ah; e->wm = wm; e->hm = hm;
  e->ow = ow; e->oh = oh; e->dir = dir; e->result = result;
  n->_cacheNext = (n->_cacheNext + 1) % TR_CACHE_SIZE;
  if (n->_cacheCount < TR_CACHE_SIZE) n->_cacheCount++;
}

/* ------------------------------------------------------------------ */
#pragma mark Zeroing hidden subtrees

static void TRZeroLayout(TRNode *n)
{
  n->_rawFrame = TRRectMake(0, 0, 0, 0);
  n->_frame = n->_rawFrame;
  n->_contentSize = TRSizeMake(0, 0);
  n->_hasPerformEntry = NO;
  for (TRNode *c in n->_children) TRZeroLayout(c);
}

/* ------------------------------------------------------------------ */
#pragma mark Flex items

typedef struct {
  __unsafe_unretained TRNode *node;
  const TRStyleStorage *s;
  TREdges edges;
  TRFloat pbMain, pbCross;
  TRFloat margin[4];           /* resolved, auto = 0 */
  BOOL marginAuto[4];
  TRFloat mainLead, mainTrail, crossLead, crossTrail;   /* margins in logical terms */
  BOOL mainLeadAuto, mainTrailAuto, crossLeadAuto, crossTrailAuto;
  TRFloat styleMain, styleCross;   /* border-box sizes from width/height, or NAN */
  TRFloat minMain, maxMain, minCross, maxCross;
  BOOL minMainIsAuto;
  BOOL basisFromContent;
  TRFloat base;                /* flex base size (border box) */
  TRFloat hypo;                /* hypothetical main size */
  TRFloat target;              /* resolved main size */
  BOOL frozen;
  TRFloat cross;               /* cross size (border box) */
  TRAlign align;
  BOOL stretched;
  TRFloat baseline;            /* from the item's cross-start margin edge */
  TRFloat mainPos, crossPos;
  NSInteger line;
} TRItem;

typedef struct {
  NSInteger start, count;
  TRFloat crossSize;
  TRFloat maxAscent, maxDescent;
  TRFloat crossPos;
} TRLine;

static int TRCompareOrder(const void *a, const void *b)
{
  const TRItem *x = a, *y = b;
  if (x->s->order != y->s->order) return x->s->order < y->s->order ? -1 : 1;
  /* qsort is not stable: fall back to document order, kept in `line`. */
  return x->line < y->line ? -1 : (x->line > y->line ? 1 : 0);
}

/* The cross-axis constraint an item is measured under: exactly the line
   when it will be stretched in a single-line container of definite cross
   size, otherwise fit-content within the available cross size. */
/* The item's own min/max cross size bound the space it is measured in:
   text in a max-width: 100px column item wraps at 100px, not at the
   container's width. */
static TRFloat TRBoundCrossAvail(const TRItem *it, TRFloat c, TRMeasureMode *mode)
{
  if (!isnan(it->maxCross))
    {
      if (*mode == TRMeasureModeUndefined) { *mode = TRMeasureModeAtMost; c = it->maxCross; }
      else c = TRMin(c, it->maxCross);
    }
  if (*mode != TRMeasureModeUndefined) c = TRMax(c, it->minCross);
  return c;
}

static TRFloat TRItemCrossAvail(TRItem *it, TRFloat availCross, TRMeasureMode crossMode,
                                BOOL multiLine, TRMeasureMode *mode)
{
  if (isnan(availCross))
    {
      *mode = TRMeasureModeUndefined;
      return TRBoundCrossAvail(it, TRUndefined, mode);
    }
  BOOL stretch = (it->align == TRAlignStretch && !it->crossLeadAuto && !it->crossTrailAuto);
  *mode = (stretch && crossMode == TRMeasureModeExactly && !multiLine)
    ? TRMeasureModeExactly : TRMeasureModeAtMost;
  return TRBoundCrossAvail(it, TRMax(0, availCross - it->crossLead - it->crossTrail), mode);
}

/* The automatic minimum size of a flex item in the main axis
   (CSS Flexbox 4.5): the content-based minimum, capped by the specified
   size, for items whose overflow is visible. */
static TRFloat TRAutoMinMain(TRItem *it, BOOL isRow, TRFloat refW, TRFloat refH,
                             TRDirection dir, TRFloat crossAvail, TRMeasureMode crossAvailMode)
{
  if (it->s->overflow != TROverflowVisible) return it->pbMain;
  TRNode *child = it->node;
  TRFloat content;
  if (isRow)
    {
      /* min-content width: lay out into zero width, fit-content. */
      TRFloat h = it->styleCross;
      TRSize sz = TRLayoutNode(child, 0, TRDefault(h, TRUndefined),
                               TRMeasureModeAtMost,
                               isnan(h) ? TRMeasureModeUndefined : TRMeasureModeExactly,
                               refW, refH, NO, dir);
      content = sz.width;
    }
  else
    {
      /* min-content height is the content height at the width the item
         will actually get (stretched, or fit-content). */
      TRFloat w = it->styleCross;
      TRMeasureMode m = TRMeasureModeExactly;
      if (isnan(w)) { w = crossAvail; m = crossAvailMode; }
      TRSize sz = TRLayoutNode(child, w, TRUndefined, isnan(w) ? TRMeasureModeUndefined : m,
                               TRMeasureModeUndefined, refW, refH, NO, dir);
      content = sz.height;
    }
  if (!isnan(it->styleMain)) content = TRMin(content, it->styleMain);
  if (!isnan(it->maxMain)) content = TRMin(content, it->maxMain);
  return TRMax(content, it->pbMain);
}

/* ------------------------------------------------------------------ */
#pragma mark Leaves

static TRSize TRLayoutLeaf(TRNode *node, const TRStyleStorage *s, const TREdges *e,
                           TRFloat aw, TRFloat ah, TRMeasureMode wm, TRMeasureMode hm)
{
  TRFloat pbW = TRPBHorizontal(e), pbH = TRPBVertical(e);
  TRFloat w, h;
  if (node->_measure != nil
      && !(wm == TRMeasureModeExactly && hm == TRMeasureModeExactly))
    {
      TRSize avail = TRSizeMake(wm == TRMeasureModeUndefined ? TRUndefined : TRMax(0, aw - pbW),
                                hm == TRMeasureModeUndefined ? TRUndefined : TRMax(0, ah - pbH));
      TRSize m = node->_measure(avail, wm, hm);
      w = wm == TRMeasureModeExactly ? aw : TRMax(0, TRDefault(m.width, 0)) + pbW;
      h = hm == TRMeasureModeExactly ? ah : TRMax(0, TRDefault(m.height, 0)) + pbH;
    }
  else
    {
      w = wm == TRMeasureModeExactly ? aw : pbW;
      h = hm == TRMeasureModeExactly ? ah : pbH;
    }
  return TRSizeMake(TRMax(w, pbW), TRMax(h, pbH));
}

/* ------------------------------------------------------------------ */
#pragma mark The flex algorithm

static TRSize TRLayoutFlex(TRNode *node, const TRStyleStorage *s, const TREdges *e,
                           TRFloat aw, TRFloat ah, TRMeasureMode wm, TRMeasureMode hm,
                           TRFloat ow, TRFloat oh, BOOL perform, TRDirection dir)
{
  /* As in CSS, an auto block size is never limited by the space on offer:
     a container whose height is only bounded takes its content height
     (its own min/max-height still apply), so its items don't shrink. */
  if (hm == TRMeasureModeAtMost) { hm = TRMeasureModeUndefined; ah = TRUndefined; }
  if (hm == TRMeasureModeUndefined)
    {
      /* ...but its own max-height does bound it (line breaking, shrinking). */
      TRFloat mh = TRBoxSize(s, s->maxHeight, oh, TRPBVertical(e));
      if (!isnan(mh)) { hm = TRMeasureModeAtMost; ah = mh; }
    }
  const BOOL rtl = (dir == TRDirectionRTL);
  const TRFlexDirection fd = (s->display == TRDisplayBlock) ? TRFlexDirectionColumn : s->flexDirection;
  const BOOL isRow = (fd == TRFlexDirectionRow || fd == TRFlexDirectionRowReverse);
  const BOOL dirReverse = (fd == TRFlexDirectionRowReverse || fd == TRFlexDirectionColumnReverse);
  const BOOL wrapReverse = (s->flexWrap == TRFlexWrapWrapReverse);
  const BOOL mainRev = isRow ? (dirReverse != rtl) : dirReverse;
  const BOOL crossRev = isRow ? wrapReverse : (rtl != wrapReverse);
  const BOOL multiLine = (s->flexWrap != TRFlexWrapNoWrap);

  const TRFloat pbW = TRPBHorizontal(e), pbH = TRPBVertical(e);
  const TRFloat pbMainC = isRow ? pbW : pbH, pbCrossC = isRow ? pbH : pbW;

  /* Available inner sizes (constraints on the content box). */
  const TRFloat innerW = wm == TRMeasureModeUndefined ? TRUndefined : TRMax(0, aw - pbW);
  const TRFloat innerH = hm == TRMeasureModeUndefined ? TRUndefined : TRMax(0, ah - pbH);
  const TRMeasureMode mainMode = isRow ? wm : hm, crossMode = isRow ? hm : wm;
  const TRFloat availMain = isRow ? innerW : innerH, availCross = isRow ? innerH : innerW;

  /* The container's own min/max, as inner sizes. */
  TRFloat minW = TRBoxSize(s, s->minWidth, ow, pbW), maxW = TRBoxSize(s, s->maxWidth, ow, pbW);
  TRFloat minH = TRBoxSize(s, s->minHeight, oh, pbH), maxH = TRBoxSize(s, s->maxHeight, oh, pbH);
  const TRFloat minInnerMain = TRMax(0, TRDefault(isRow ? minW : minH, 0) - pbMainC);
  const TRFloat maxInnerMain = isnan(isRow ? maxW : maxH) ? TRUndefined : TRMax(0, (isRow ? maxW : maxH) - pbMainC);
  const TRFloat minInnerCross = TRMax(0, TRDefault(isRow ? minH : minW, 0) - pbCrossC);
  const TRFloat maxInnerCross = isnan(isRow ? maxH : maxW) ? TRUndefined : TRMax(0, (isRow ? maxH : maxW) - pbCrossC);

  /* Children resolve percentages against these. A size that is only an
     upper bound (fit-content) is indefinite, so percentages act as auto
     until the final, exact layout. */
  const TRFloat refW = wm == TRMeasureModeExactly ? innerW : TRUndefined;
  const TRFloat refH = hm == TRMeasureModeExactly ? innerH : TRUndefined;
  const TRFloat refMain = isRow ? refW : refH, refCross = isRow ? refH : refW;

  const TRFloat mainGap = TRMax(0, TRDefault(TRResolve(isRow ? s->columnGap : s->rowGap, refMain), 0));
  const TRFloat crossGap = TRMax(0, TRDefault(TRResolve(isRow ? s->rowGap : s->columnGap, refCross), 0));

  const TREdge mainLeadE = TRLeadingEdge(isRow, mainRev), mainTrailE = TRTrailingEdge(isRow, mainRev);
  const TREdge crossLeadE = TRLeadingEdge(!isRow, crossRev), crossTrailE = TRTrailingEdge(!isRow, crossRev);

  /* ---- Collect in-flow items ---- */
  NSArray<TRNode *> *children = node->_children;
  NSUInteger nChildren = [children count];
  TRItem *items = calloc(nChildren ? nChildren : 1, sizeof(TRItem));
  NSInteger n = 0;
  for (NSUInteger ci = 0; ci < nChildren; ci++)
    {
      TRNode *child = children[ci];
      const TRStyleStorage *cs = &child->_style->_s;
      if (cs->display == TRDisplayNone)
        {
          if (perform) TRZeroLayout(child);
          continue;
        }
      if (cs->position == TRPositionAbsolute) continue;
      TRItem *it = &items[n++];
      it->node = child;
      it->s = cs;
      it->line = (NSInteger)ci;   /* document order, for the stable sort */
    }
  if (n > 1) qsort(items, (size_t)n, sizeof(TRItem), TRCompareOrder);

  /* ---- Flex base sizes and hypothetical main sizes (9.2) ---- */
  for (NSInteger i = 0; i < n; i++)
    {
      TRItem *it = &items[i];
      const TRStyleStorage *cs = it->s;
      it->edges = TRResolveEdges(cs, refW);
      TRFloat cpbW = TRPBHorizontal(&it->edges), cpbH = TRPBVertical(&it->edges);
      it->pbMain = isRow ? cpbW : cpbH;
      it->pbCross = isRow ? cpbH : cpbW;
      for (int k = 0; k < 4; k++)
        {
          it->marginAuto[k] = (cs->margin[k].unit == TRUnitAuto);
          /* Margin percentages resolve against the container's inline size. */
          it->margin[k] = TRDefault(TRResolve(cs->margin[k], refW), 0);
        }
      it->mainLead = it->margin[mainLeadE]; it->mainTrail = it->margin[mainTrailE];
      it->crossLead = it->margin[crossLeadE]; it->crossTrail = it->margin[crossTrailE];
      it->mainLeadAuto = it->marginAuto[mainLeadE]; it->mainTrailAuto = it->marginAuto[mainTrailE];
      it->crossLeadAuto = it->marginAuto[crossLeadE]; it->crossTrailAuto = it->marginAuto[crossTrailE];

      TRFloat sw = TRBoxSize(cs, cs->width, refW, cpbW);
      TRFloat sh = TRBoxSize(cs, cs->height, refH, cpbH);
      it->styleMain = isRow ? sw : sh;
      it->styleCross = isRow ? sh : sw;

      TRFloat mnW = TRBoxSize(cs, cs->minWidth, refW, cpbW), mxW = TRBoxSize(cs, cs->maxWidth, refW, cpbW);
      TRFloat mnH = TRBoxSize(cs, cs->minHeight, refH, cpbH), mxH = TRBoxSize(cs, cs->maxHeight, refH, cpbH);
      TRValue minMainV = isRow ? cs->minWidth : cs->minHeight;
      it->minMainIsAuto = (minMainV.unit == TRUnitAuto);
      it->minMain = TRMax(TRDefault(isRow ? mnW : mnH, 0), it->pbMain);
      it->maxMain = isRow ? mxW : mxH;
      it->minCross = TRMax(TRDefault(isRow ? mnH : mnW, 0), it->pbCross);
      it->maxCross = isRow ? mxH : mxW;

      it->align = TRResolveAlignSelf(cs, s);
      if (!isRow && it->align == TRAlignBaseline) it->align = TRAlignFlexStart;

      /* Aspect ratio transfers a definite cross size to the main axis. */
      TRFloat ar = cs->aspectRatio;
      if (isnan(it->styleMain) && !isnan(it->styleCross) && !isnan(ar))
        {
          TRFloat crossContent = cs->boxSizing == TRBoxSizingContentBox ? it->styleCross - it->pbCross : it->styleCross;
          TRFloat mainContent = isRow ? crossContent * ar : crossContent / ar;
          it->styleMain = cs->boxSizing == TRBoxSizingContentBox ? mainContent + it->pbMain : TRMax(mainContent, it->pbMain);
        }

      /* flex-basis */
      TRFloat basis = TRUndefined;
      if (cs->flexBasis.unit == TRUnitPoint || cs->flexBasis.unit == TRUnitPercent)
        basis = TRBoxSize(cs, cs->flexBasis, refMain, it->pbMain);
      if (isnan(basis) && !isnan(it->styleMain))
        basis = it->styleMain;
      if (isnan(basis))
        {
          /* Size the item under a max-content constraint in the main axis. */
          it->basisFromContent = YES;
          TRFloat cw = sw, ch = sh;
          TRMeasureMode cwm = isnan(cw) ? TRMeasureModeUndefined : TRMeasureModeExactly;
          TRMeasureMode chm = isnan(ch) ? TRMeasureModeUndefined : TRMeasureModeExactly;
          if (isnan(it->styleCross))
            {
              TRMeasureMode cm;
              TRFloat c = TRItemCrossAvail(it, availCross, crossMode, multiLine, &cm);
              if (isRow) { ch = c; chm = cm; } else { cw = c; cwm = cm; }
            }
          if (!isnan(ar) && (isRow ? chm : cwm) == TRMeasureModeExactly)
            {
              TRFloat crossBox = isRow ? ch : cw;
              TRFloat crossContent = cs->boxSizing == TRBoxSizingContentBox ? crossBox - it->pbCross : crossBox;
              TRFloat mainContent = isRow ? crossContent * ar : crossContent / ar;
              basis = cs->boxSizing == TRBoxSizingContentBox ? mainContent + it->pbMain : mainContent;
            }
          else
            {
              TRSize sz = TRLayoutNode(it->node, cw, ch, cwm, chm, refW, refH, NO, dir);
              basis = isRow ? sz.width : sz.height;
            }
        }
      it->base = TRMax(basis, it->pbMain);

      /* With an explicit basis, the automatic minimum can exceed it
         (e.g. flex: 1 on text never shrinks below its longest word). */
      if (it->minMainIsAuto && !it->basisFromContent)
        {
          TRMeasureMode cm;
          TRFloat ca = TRItemCrossAvail(it, availCross, crossMode, multiLine, &cm);
          it->minMain = TRAutoMinMain(it, isRow, refW, refH, dir, ca, cm);
        }
      it->hypo = TRClamp(it->base, it->minMain, it->maxMain);
    }

  /* ---- Collect items into flex lines (9.3) ---- */
  TRLine *lines = calloc((size_t)(n ? n : 1), sizeof(TRLine));
  NSInteger nLines = 0;
  {
    NSInteger i = 0;
    while (i < n)
      {
        TRLine *ln = &lines[nLines++];
        ln->start = i;
        TRFloat used = 0;
        NSInteger count = 0;
        for (; i < n; i++)
          {
            TRItem *it = &items[i];
            TRFloat outer = it->hypo + it->mainLead + it->mainTrail;
            TRFloat add = outer + (count > 0 ? mainGap : 0);
            if (multiLine && count > 0 && !isnan(availMain) && used + add > availMain + 0.0001)
              break;
            used += add;
            it->line = nLines - 1;
            count++;
          }
        ln->count = count;
      }
  }

  /* ---- Resolve flexible lengths, per line (9.7) ---- */
  TRFloat maxLineMain = 0;
  for (NSInteger l = 0; l < nLines; l++)
    {
      TRLine *ln = &lines[l];
      TRItem *li = &items[ln->start];
      NSInteger cnt = ln->count;
      TRFloat gaps = cnt > 1 ? mainGap * (cnt - 1) : 0;
      TRFloat sumHypo = gaps;
      for (NSInteger j = 0; j < cnt; j++)
        sumHypo += li[j].hypo + li[j].mainLead + li[j].mainTrail;

      TRFloat space;
      if (mainMode == TRMeasureModeExactly)
        space = availMain;
      else
        {
          /* Intrinsic (fit-content / max-content) sizing: the line's
             content size is the sum of the items' max-content
             contributions (CSS Flexbox 9.9.1), not their flex-basis sizes,
             so `flex: 1` text does not collapse to its min-content. */
          TRFloat content = gaps;
          for (NSInteger j = 0; j < cnt; j++)
            {
              TRItem *it = &li[j];
              TRFloat contrib = it->hypo;
              if (!it->basisFromContent && it->s->flexGrow > 0)
                {
                  TRMeasureMode cm;
                  TRFloat ca = TRItemCrossAvail(it, availCross, crossMode, multiLine, &cm);
                  TRSize mc = isRow
                    ? TRLayoutNode(it->node, TRUndefined, ca, TRMeasureModeUndefined, cm, refW, refH, NO, dir)
                    : TRLayoutNode(it->node, ca, TRUndefined, cm, TRMeasureModeUndefined, refW, refH, NO, dir);
                  TRFloat m = TRClamp(isRow ? mc.width : mc.height, it->minMain, it->maxMain);
                  if (!isnan(it->styleMain)) m = it->styleMain;
                  contrib = TRMax(contrib, m);
                }
              content += contrib + it->mainLead + it->mainTrail;
            }
          TRFloat hi = maxInnerMain;
          if (mainMode == TRMeasureModeAtMost)
            hi = isnan(hi) ? availMain : TRMin(hi, availMain);
          space = TRClamp(TRMax(content, sumHypo), minInnerMain, hi);
        }
      BOOL growing = sumHypo < space;
      for (NSInteger j = 0; j < cnt; j++)
        {
          TRItem *it = &li[j];
          it->target = it->hypo;
          TRFloat factor = growing ? it->s->flexGrow : it->s->flexShrink;
          it->frozen = (factor == 0)
            || (growing && it->base > it->hypo)
            || (!growing && it->base < it->hypo)
            || TRFloatsEqual(sumHypo, space);
          if (!growing && !it->frozen && it->minMainIsAuto && it->basisFromContent)
            {
              TRMeasureMode cm;
              TRFloat ca = TRItemCrossAvail(it, availCross, crossMode, multiLine, &cm);
              it->minMain = TRAutoMinMain(it, isRow, refW, refH, dir, ca, cm);
            }
        }

      TRFloat initialFree = space - gaps;
      for (NSInteger j = 0; j < cnt; j++)
        {
          TRItem *it = &li[j];
          initialFree -= (it->frozen ? it->target : it->base) + it->mainLead + it->mainTrail;
        }

      for (int guard = 0; guard < 64; guard++)
        {
          BOOL anyUnfrozen = NO;
          TRFloat free = space - gaps, sumFlex = 0, sumScaled = 0;
          for (NSInteger j = 0; j < cnt; j++)
            {
              TRItem *it = &li[j];
              free -= (it->frozen ? it->target : it->base) + it->mainLead + it->mainTrail;
              if (!it->frozen)
                {
                  anyUnfrozen = YES;
                  sumFlex += growing ? it->s->flexGrow : it->s->flexShrink;
                  sumScaled += it->s->flexShrink * (it->base - it->pbMain);
                }
            }
          if (!anyUnfrozen) break;
          if (sumFlex < 1)
            {
              TRFloat t = initialFree * sumFlex;
              if (fabs(t) < fabs(free)) free = t;
            }

          TRFloat totalViolation = 0;
          for (NSInteger j = 0; j < cnt; j++)
            {
              TRItem *it = &li[j];
              if (it->frozen) continue;
              TRFloat t = it->base;
              if (growing && sumFlex > 0)
                t = it->base + free * (it->s->flexGrow / sumFlex);
              else if (!growing && sumScaled > 0)
                t = it->base + free * (it->s->flexShrink * (it->base - it->pbMain) / sumScaled);
              TRFloat clamped = TRMax(TRClamp(t, it->minMain, it->maxMain), it->pbMain);
              it->target = clamped;
              totalViolation += clamped - t;
              /* stash the raw value's sign in `cross` temporarily */
              it->cross = clamped - t;
            }
          for (NSInteger j = 0; j < cnt; j++)
            {
              TRItem *it = &li[j];
              if (it->frozen) continue;
              if (fabs(totalViolation) < 0.0001) it->frozen = YES;
              else if (totalViolation > 0 && it->cross > 0) it->frozen = YES;
              else if (totalViolation < 0 && it->cross < 0) it->frozen = YES;
            }
          if (fabs(totalViolation) < 0.0001) break;
        }

      TRFloat lineMain = gaps;
      for (NSInteger j = 0; j < cnt; j++)
        lineMain += li[j].target + li[j].mainLead + li[j].mainTrail;
      maxLineMain = TRMax(maxLineMain, lineMain);
    }

  /* ---- The container's inner main size ---- */
  TRFloat innerMain;
  if (mainMode == TRMeasureModeExactly)
    innerMain = availMain;
  else
    {
      /* fit-content: min(max-content, max(min-content, available)). Items
         were already shrunk towards availMain, so a line longer than that is
         at its min-content and the container grows to hold it; a container
         that wrapped has max-content > available, so it takes availMain. */
      TRFloat content = maxLineMain;
      if (mainMode == TRMeasureModeAtMost && nLines > 1) content = TRMax(content, availMain);
      innerMain = TRClamp(content, minInnerMain, maxInnerMain);
      innerMain = TRMax(innerMain, 0);
    }

  /* ---- Hypothetical cross sizes (9.4) ---- */
  for (NSInteger i = 0; i < n; i++)
    {
      TRItem *it = &items[i];
      const TRStyleStorage *cs = it->s;
      it->cross = TRUndefined;
      if (!isnan(it->styleCross))
        it->cross = it->styleCross;
      else if (!isnan(cs->aspectRatio))
        {
          TRFloat mainContent = cs->boxSizing == TRBoxSizingContentBox ? it->target - it->pbMain : it->target;
          TRFloat crossContent = isRow ? mainContent / cs->aspectRatio : mainContent * cs->aspectRatio;
          it->cross = cs->boxSizing == TRBoxSizingContentBox ? crossContent + it->pbCross : crossContent;
        }
      else
        {
          TRMeasureMode cm;
          TRFloat c = TRItemCrossAvail(it, availCross, crossMode, multiLine, &cm);
          TRSize sz = isRow
            ? TRLayoutNode(it->node, it->target, c, TRMeasureModeExactly, cm, refW, refH, NO, dir)
            : TRLayoutNode(it->node, c, it->target, cm, TRMeasureModeExactly, refW, refH, NO, dir);
          it->cross = isRow ? sz.height : sz.width;
        }
      it->cross = TRMax(TRClamp(it->cross, it->minCross, it->maxCross), it->pbCross);
    }

  /* ---- Line cross sizes, with baselines (9.4 step 8) ---- */
  for (NSInteger l = 0; l < nLines; l++)
    {
      TRLine *ln = &lines[l];
      TRFloat maxOuter = 0, maxAsc = 0, maxDesc = 0;
      for (NSInteger j = ln->start; j < ln->start + ln->count; j++)
        {
          TRItem *it = &items[j];
          TRFloat outer = it->cross + it->crossLead + it->crossTrail;
          if (it->align == TRAlignBaseline && !it->crossLeadAuto && !it->crossTrailAuto)
            {
              TRLayoutNode(it->node, it->target, it->cross,
                           TRMeasureModeExactly, TRMeasureModeExactly, refW, refH, YES, dir);
              TRFloat b = TRComputeBaseline(it->node);
              /* In wrap-reverse, the cross-start edge is the bottom. */
              if (crossRev) b = it->cross - b;
              it->baseline = b + it->crossLead;
              maxAsc = TRMax(maxAsc, it->baseline);
              maxDesc = TRMax(maxDesc, outer - it->baseline);
            }
          else
            maxOuter = TRMax(maxOuter, outer);
        }
      ln->maxAscent = maxAsc;
      ln->maxDescent = maxDesc;
      ln->crossSize = TRMax(maxOuter, maxAsc + maxDesc);
    }
  if (!multiLine && nLines == 1)
    {
      if (crossMode == TRMeasureModeExactly)
        lines[0].crossSize = availCross;
      else
        lines[0].crossSize = TRClamp(lines[0].crossSize, minInnerCross, maxInnerCross);
    }

  /* ---- The container's inner cross size ---- */
  TRFloat totalCross = 0;
  for (NSInteger l = 0; l < nLines; l++)
    totalCross += lines[l].crossSize + (l > 0 ? crossGap : 0);
  TRFloat innerCross;
  if (crossMode == TRMeasureModeExactly)
    innerCross = availCross;
  else
    {
      /* Items were measured at most availCross; one that is larger cannot
         be narrower (its min-content), so the container holds it. */
      innerCross = TRClamp(totalCross, minInnerCross, maxInnerCross);
      innerCross = TRMax(innerCross, 0);
    }

  /* ---- align-content (9.4 step 15, 9.6) ---- */
  TRFloat acLead = 0, acBetween = 0;
  if (!multiLine)
    {
      if (nLines == 1) lines[0].crossSize = innerCross;
    }
  else
    {
      TRFloat free = innerCross - totalCross;
      TRAlign ac = s->alignContent;
      if (ac == TRAlignNormal) ac = TRAlignStretch;
      if (ac == TRAlignStart) ac = TRAlignFlexStart;   /* refined below */
      if (s->alignContent == TRAlignStart) ac = wrapReverse ? TRAlignFlexEnd : TRAlignFlexStart;
      if (s->alignContent == TRAlignEnd || s->alignContent == TRAlignLastBaseline)
        ac = wrapReverse ? TRAlignFlexStart : TRAlignFlexEnd;
      switch (ac)
        {
          case TRAlignStretch:
            if (free > 0 && nLines > 0)
              for (NSInteger l = 0; l < nLines; l++) lines[l].crossSize += free / nLines;
            break;
          case TRAlignFlexEnd: acLead = free; break;
          case TRAlignCenter: acLead = free / 2; break;
          case TRAlignSpaceBetween:
            if (free > 0 && nLines > 1) acBetween = free / (nLines - 1);
            break;
          /* Negative space: these fall back to 'safe center', i.e. 'start'. */
          case TRAlignSpaceAround:
            if (free > 0) { acBetween = free / nLines; acLead = acBetween / 2; }
            else acLead = wrapReverse ? free : 0;
            break;
          case TRAlignSpaceEvenly:
            if (free > 0) { acBetween = free / (nLines + 1); acLead = acBetween; }
            else acLead = wrapReverse ? free : 0;
            break;
          default: break;
        }
    }

  /* ---- Stretch, then the final cross size of each item (9.4 step 11) ---- */
  for (NSInteger i = 0; i < n; i++)
    {
      TRItem *it = &items[i];
      TRLine *ln = &lines[it->line];
      if (it->align == TRAlignStretch && isnan(it->styleCross)
          && !it->crossLeadAuto && !it->crossTrailAuto)
        {
          TRFloat c = ln->crossSize - it->crossLead - it->crossTrail;
          it->cross = TRMax(TRClamp(c, it->minCross, it->maxCross), it->pbCross);
          it->stretched = YES;
        }
    }

  /* ---- Main-axis alignment (9.5) ---- */
  TRAlign jc = s->justifyContent;
  if (jc == TRAlignNormal || jc == TRAlignStretch) jc = TRAlignFlexStart;
  if (jc == TRAlignLeft || jc == TRAlignRight)
    {
      /* Physical: in a column (main axis not the inline axis) they act as
         'start'; in a row, left is the start only in ltr. */
      if (!isRow) jc = TRAlignStart;
      else jc = ((jc == TRAlignLeft) == !rtl) ? TRAlignStart : TRAlignEnd;
    }
  /* start/end follow the writing mode, not the flex direction. */
  BOOL startIsFlexStart = isRow ? (rtl == mainRev) : !mainRev;
  if (jc == TRAlignStart || jc == TRAlignEnd)
    {
      BOOL wantStart = (jc == TRAlignStart);
      jc = (wantStart == startIsFlexStart) ? TRAlignFlexStart : TRAlignFlexEnd;
    }
  for (NSInteger l = 0; l < nLines; l++)
    {
      TRLine *ln = &lines[l];
      TRItem *li = &items[ln->start];
      NSInteger cnt = ln->count;
      TRFloat used = cnt > 1 ? mainGap * (cnt - 1) : 0;
      int autoMargins = 0;
      for (NSInteger j = 0; j < cnt; j++)
        {
          used += li[j].target + li[j].mainLead + li[j].mainTrail;
          autoMargins += li[j].mainLeadAuto + li[j].mainTrailAuto;
        }
      TRFloat free = innerMain - used;
      TRFloat lead = 0, between = 0, autoShare = 0;
      if (autoMargins > 0 && free > 0)
        autoShare = free / autoMargins;
      else
        switch (jc)
          {
            case TRAlignFlexEnd: lead = free; break;
            case TRAlignCenter: lead = free / 2; break;
            case TRAlignSpaceBetween:
              if (free > 0 && cnt > 1) between = free / (cnt - 1);
              break;
            /* Negative space: these fall back to 'safe center', i.e. 'start'. */
            case TRAlignSpaceAround:
              if (free > 0 && cnt > 0) { between = free / cnt; lead = between / 2; }
              else lead = startIsFlexStart ? 0 : free;
              break;
            case TRAlignSpaceEvenly:
              if (free > 0) { between = free / (cnt + 1); lead = between; }
              else lead = startIsFlexStart ? 0 : free;
              break;
            default: break;
          }
      TRFloat pos = lead;
      for (NSInteger j = 0; j < cnt; j++)
        {
          TRItem *it = &li[j];
          if (it->mainLeadAuto) it->mainLead = autoShare;
          if (it->mainTrailAuto) it->mainTrail = autoShare;
          pos += it->mainLead;
          it->mainPos = pos;
          pos += it->target + it->mainTrail + between + (j + 1 < cnt ? mainGap : 0);
        }
    }

  /* ---- Cross-axis alignment (9.6) ---- */
  {
    TRFloat linePos = acLead;
    for (NSInteger l = 0; l < nLines; l++)
      {
        TRLine *ln = &lines[l];
        ln->crossPos = linePos;
        for (NSInteger j = ln->start; j < ln->start + ln->count; j++)
          {
            TRItem *it = &items[j];
            TRFloat outer = it->cross + it->crossLead + it->crossTrail;
            TRFloat free = ln->crossSize - outer;
            TRFloat off = 0;
            if (it->crossLeadAuto || it->crossTrailAuto)
              {
                if (free > 0)
                  {
                    if (it->crossLeadAuto && it->crossTrailAuto) off = free / 2;
                    else if (it->crossLeadAuto) off = free;
                  }
              }
            else
              {
                TRAlign a = it->align;
                if (a == TRAlignStart) a = wrapReverse ? TRAlignFlexEnd : TRAlignFlexStart;
                else if (a == TRAlignEnd) a = wrapReverse ? TRAlignFlexStart : TRAlignFlexEnd;
                switch (a)
                  {
                    case TRAlignFlexEnd: off = free; break;
                    case TRAlignCenter: off = free / 2; break;
                    case TRAlignBaseline: off = ln->maxAscent - it->baseline; break;
                    default: break;
                  }
              }
            it->crossPos = linePos + off + it->crossLead;
          }
        linePos += ln->crossSize + crossGap + acBetween;
      }
  }

  /* ---- The container's size ---- */
  TRFloat W = isRow ? innerMain + pbW : innerCross + pbW;
  TRFloat H = isRow ? innerCross + pbH : innerMain + pbH;
  if (wm == TRMeasureModeExactly) W = aw;
  if (hm == TRMeasureModeExactly) H = ah;
  W = TRMax(W, pbW);
  H = TRMax(H, pbH);

  /* ---- Final layout of the items ---- */
  if (perform)
    {
      const TRFloat finalInnerMain = (isRow ? W - pbW : H - pbH);
      const TRFloat finalInnerCross = (isRow ? H - pbH : W - pbW);
      TRFloat maxX = 0, maxY = 0;
      for (NSInteger i = 0; i < n; i++)
        {
          TRItem *it = &items[i];
          TRFloat w = isRow ? it->target : it->cross;
          TRFloat h = isRow ? it->cross : it->target;
          TRLayoutNode(it->node, w, h, TRMeasureModeExactly, TRMeasureModeExactly,
                       refW, refH, YES, dir);
          TRFloat mainPhys = mainRev ? finalInnerMain - it->mainPos - it->target : it->mainPos;
          TRFloat crossPhys = crossRev ? finalInnerCross - it->crossPos - it->cross : it->crossPos;
          TRFloat x = e->pad[TREdgeLeft] + e->border[TREdgeLeft] + (isRow ? mainPhys : crossPhys);
          TRFloat y = e->pad[TREdgeTop] + e->border[TREdgeTop] + (isRow ? crossPhys : mainPhys);
          const TRStyleStorage *cs = it->s;
          if (cs->position == TRPositionRelative)
            {
              TRFloat l = TRResolve(cs->inset[TREdgeLeft], refW), r = TRResolve(cs->inset[TREdgeRight], refW);
              TRFloat t = TRResolve(cs->inset[TREdgeTop], refH), b = TRResolve(cs->inset[TREdgeBottom], refH);
              x += !isnan(l) ? l : (!isnan(r) ? -r : 0);
              y += !isnan(t) ? t : (!isnan(b) ? -b : 0);
            }
          TRNode *c = it->node;
          c->_rawFrame = TRRectMake(x, y, w, h);
          c->_lineIndex = it->line;
          for (int k = 0; k < 4; k++) c->_lmargin[k] = it->margin[k];
          c->_lmargin[mainLeadE] = it->mainLead;
          c->_lmargin[mainTrailE] = it->mainTrail;
          maxX = TRMax(maxX, x + w + c->_lmargin[TREdgeRight]);
          maxY = TRMax(maxY, y + h + c->_lmargin[TREdgeBottom]);
        }

      /* ---- Absolutely positioned children ---- */
      TRFloat cbW = W - e->border[TREdgeLeft] - e->border[TREdgeRight];
      TRFloat cbH = H - e->border[TREdgeTop] - e->border[TREdgeBottom];
      for (NSUInteger ci = 0; ci < nChildren; ci++)
        {
          TRNode *c = children[ci];
          const TRStyleStorage *cs = &c->_style->_s;
          if (cs->display == TRDisplayNone || cs->position != TRPositionAbsolute) continue;
          TREdges ce = TRResolveEdges(cs, cbW);
          TRFloat cpbW = TRPBHorizontal(&ce), cpbH = TRPBVertical(&ce);
          TRFloat m[4];
          for (int k = 0; k < 4; k++) m[k] = TRDefault(TRResolve(cs->margin[k], cbW), 0);
          TRFloat L = TRResolve(cs->inset[TREdgeLeft], cbW), R = TRResolve(cs->inset[TREdgeRight], cbW);
          TRFloat T = TRResolve(cs->inset[TREdgeTop], cbH), B = TRResolve(cs->inset[TREdgeBottom], cbH);
          TRFloat w = TRBoxSize(cs, cs->width, cbW, cpbW);
          TRFloat h = TRBoxSize(cs, cs->height, cbH, cpbH);
          if (isnan(w) && !isnan(L) && !isnan(R))
            w = TRMax(cpbW, cbW - L - R - m[TREdgeLeft] - m[TREdgeRight]);
          if (isnan(h) && !isnan(T) && !isnan(B))
            h = TRMax(cpbH, cbH - T - B - m[TREdgeTop] - m[TREdgeBottom]);
          TRFloat ar = cs->aspectRatio;
          if (!isnan(ar))
            {
              if (isnan(w) && !isnan(h)) w = h * ar;
              else if (isnan(h) && !isnan(w)) h = w / ar;
            }
          if (isnan(w) || isnan(h))
            {
              TRFloat availW = cbW - TRDefault(L, 0) - TRDefault(R, 0) - m[TREdgeLeft] - m[TREdgeRight];
              TRSize sz = TRLayoutNode(c, isnan(w) ? TRMax(0, availW) : w, TRDefault(h, TRUndefined),
                                       isnan(w) ? TRMeasureModeAtMost : TRMeasureModeExactly,
                                       isnan(h) ? TRMeasureModeUndefined : TRMeasureModeExactly,
                                       cbW, cbH, NO, dir);
              if (isnan(w)) w = sz.width;
              if (isnan(h)) h = sz.height;
            }
          w = TRMax(TRClamp(w, TRBoxSize(cs, cs->minWidth, cbW, cpbW), TRBoxSize(cs, cs->maxWidth, cbW, cpbW)), cpbW);
          h = TRMax(TRClamp(h, TRBoxSize(cs, cs->minHeight, cbH, cpbH), TRBoxSize(cs, cs->maxHeight, cbH, cpbH)), cpbH);
          TRLayoutNode(c, w, h, TRMeasureModeExactly, TRMeasureModeExactly, cbW, cbH, YES, dir);

          /* Static position: as if the sole flex item in the content box. */
          TRFloat outerW = w + m[TREdgeLeft] + m[TREdgeRight];
          TRFloat outerH = h + m[TREdgeTop] + m[TREdgeBottom];
          TRFloat contentW = W - pbW, contentH = H - pbH;
          TRFloat staticX, staticY;
          {
            TRFloat freeMain = (isRow ? contentW - outerW : contentH - outerH);
            TRFloat freeCross = (isRow ? contentH - outerH : contentW - outerW);
            TRFloat offMain = 0, offCross = 0;
            switch (jc)
              {
                case TRAlignFlexEnd: offMain = freeMain; break;
                case TRAlignCenter: case TRAlignSpaceAround: case TRAlignSpaceEvenly:
                  offMain = freeMain / 2; break;
                default: break;
              }
            TRAlign a = TRResolveAlignSelf(cs, s);
            /* An abspos box has no baseline set to join: CSS Align falls
               back to 'start' (not 'flex-start'), which ignores wrap-reverse. */
            if (a == TRAlignBaseline) a = TRAlignStart;
            if (a == TRAlignStart) a = wrapReverse ? TRAlignFlexEnd : TRAlignFlexStart;
            else if (a == TRAlignEnd) a = wrapReverse ? TRAlignFlexStart : TRAlignFlexEnd;
            if (a == TRAlignFlexEnd) offCross = freeCross;
            else if (a == TRAlignCenter) offCross = freeCross / 2;
            TRFloat mainSize = isRow ? outerW : outerH, crossSize = isRow ? outerH : outerW;
            TRFloat mainPhys = mainRev ? (isRow ? contentW : contentH) - offMain - mainSize : offMain;
            TRFloat crossPhys = crossRev ? (isRow ? contentH : contentW) - offCross - crossSize : offCross;
            staticX = e->pad[TREdgeLeft] + e->border[TREdgeLeft] + (isRow ? mainPhys : crossPhys) + m[TREdgeLeft];
            staticY = e->pad[TREdgeTop] + e->border[TREdgeTop] + (isRow ? crossPhys : mainPhys) + m[TREdgeTop];
          }
          TRFloat x, y;
          /* Over-constrained (left, right and width): rtl honours right. */
          if (!isnan(L) && !(rtl && !isnan(R))) x = e->border[TREdgeLeft] + L + m[TREdgeLeft];
          else if (!isnan(R)) x = W - e->border[TREdgeRight] - R - m[TREdgeRight] - w;
          else x = staticX;
          if (!isnan(T)) y = e->border[TREdgeTop] + T + m[TREdgeTop];
          else if (!isnan(B)) y = H - e->border[TREdgeBottom] - B - m[TREdgeBottom] - h;
          else y = staticY;
          c->_rawFrame = TRRectMake(x, y, w, h);
          for (int k = 0; k < 4; k++) c->_lmargin[k] = m[k];
          c->_lineIndex = -1;
        }

      node->_contentSize = TRSizeMake(TRMax(W, maxX + e->pad[TREdgeRight] + e->border[TREdgeRight]),
                                      TRMax(H, maxY + e->pad[TREdgeBottom] + e->border[TREdgeBottom]));
    }

  free(lines);
  free(items);
  return TRSizeMake(W, H);
}

/* ------------------------------------------------------------------ */
#pragma mark Entry point

TRSize TRLayoutNode(TRNode *node, TRFloat aw, TRFloat ah,
                    TRMeasureMode wm, TRMeasureMode hm,
                    TRFloat ow, TRFloat oh, BOOL perform,
                    TRDirection parentDirection)
{
  const TRStyleStorage *s = &node->_style->_s;
  TRDirection dir = s->direction == TRDirectionInherit ? parentDirection : s->direction;
  if (dir == TRDirectionInherit) dir = TRDirectionLTR;
  if (wm == TRMeasureModeUndefined) aw = TRUndefined;
  if (hm == TRMeasureModeUndefined) ah = TRUndefined;

  /* Cache lookup. A perform must also redo a grid/flex container whose
     children's percentages depend on ow/oh only via its own inner size,
     which is covered by aw/ah. */
  BOOL ownerMatters = TRUsesOwnerSize(s);
  if (perform)
    {
      if (node->_hasPerformEntry
          && TRCacheMatch(&node->_performEntry, aw, ah, wm, hm, ow, oh, dir, ownerMatters))
        return node->_performEntry.result;
    }
  else
    {
      if (node->_hasPerformEntry
          && TRCacheMatch(&node->_performEntry, aw, ah, wm, hm, ow, oh, dir, ownerMatters))
        return node->_performEntry.result;
      for (int i = 0; i < node->_cacheCount; i++)
        if (TRCacheMatch(&node->_cache[i], aw, ah, wm, hm, ow, oh, dir, ownerMatters))
          return node->_cache[i].result;
    }

  TREdges e = TRResolveEdges(s, ow);
  TRFloat pbW = TRPBHorizontal(&e), pbH = TRPBVertical(&e);

  BOOL hasInFlowOrAbs = NO;
  for (TRNode *c in node->_children)
    if (c->_style->_s.display != TRDisplayNone) { hasInFlowOrAbs = YES; break; }

  TRSize size;
  if (s->display == TRDisplayGrid)
    {
      size = TRLayoutGrid(node, s, e.pad, e.border, aw, ah, wm, hm, ow, oh, perform, dir);
      hasInFlowOrAbs = YES;   /* the grid set _contentSize */
    }
  else if (!hasInFlowOrAbs)
    {
      if (perform)
        for (TRNode *c in node->_children) TRZeroLayout(c);
      size = TRLayoutLeaf(node, s, &e, aw, ah, wm, hm);
    }
  else
    size = TRLayoutFlex(node, s, &e, aw, ah, wm, hm, ow, oh, perform, dir);

  /* The node's own min/max apply to dimensions it chose itself. */
  if (wm != TRMeasureModeExactly)
    size.width = TRMax(TRClamp(size.width, TRBoxSize(s, s->minWidth, ow, pbW),
                               TRBoxSize(s, s->maxWidth, ow, pbW)), pbW);
  if (hm != TRMeasureModeExactly)
    size.height = TRMax(TRClamp(size.height, TRBoxSize(s, s->minHeight, oh, pbH),
                                TRBoxSize(s, s->maxHeight, oh, pbH)), pbH);

  if (perform)
    {
      node->_rawFrame.width = size.width;
      node->_rawFrame.height = size.height;
      node->_ldir = dir;
      for (int k = 0; k < 4; k++)
        {
          node->_lpad[k] = e.pad[k];
          node->_lborder[k] = e.border[k];
        }
      if (!hasInFlowOrAbs) node->_contentSize = size;
      node->_hasPerformEntry = YES;
      TRCacheEntry *pe = &node->_performEntry;
      pe->aw = aw; pe->ah = ah; pe->wm = wm; pe->hm = hm;
      pe->ow = ow; pe->oh = oh; pe->dir = dir; pe->result = size;
    }
  else
    TRCacheStore(node, aw, ah, wm, hm, ow, oh, dir, size);
  return size;
}

/* ------------------------------------------------------------------ */
#pragma mark Baselines

TRFloat TRComputeBaseline(TRNode *node)
{
  if (node->_baselineFn != nil)
    return node->_baselineFn(TRSizeMake(node->_rawFrame.width, node->_rawFrame.height));
  const TRStyleStorage *s = &node->_style->_s;
  BOOL isRow = s->display != TRDisplayBlock
    && (s->flexDirection == TRFlexDirectionRow || s->flexDirection == TRFlexDirectionRowReverse);
  TRNode *best = nil;
  NSInteger bestOrder = NSIntegerMax;
  for (TRNode *c in node->_children)
    {
      if (!TRIsInFlow(c) || c->_lineIndex != 0) continue;
      const TRStyleStorage *cs = &c->_style->_s;
      if (isRow && TRResolveAlignSelf(cs, s) == TRAlignBaseline)
        { best = c; break; }
      if (best == nil || cs->order < bestOrder)
        { best = c; bestOrder = cs->order; }
    }
  if (best == nil) return node->_rawFrame.height;
  return TRComputeBaseline(best) + best->_rawFrame.y;
}

/* ------------------------------------------------------------------ */
#pragma mark Pixel-grid rounding (Yoga-compatible)

static TRFloat TRRoundToGrid(TRFloat v, TRFloat scale, BOOL forceCeil, BOOL forceFloor)
{
  TRFloat scaled = v * scale;
  TRFloat frac = fmod(scaled, 1.0);
  if (frac < 0) frac += 1.0;
  if (fabs(frac) < 0.0001) scaled -= frac;
  else if (fabs(frac - 1.0) < 0.0001) scaled = scaled - frac + 1.0;
  else if (forceCeil) scaled = scaled - frac + 1.0;
  else if (forceFloor) scaled -= frac;
  else scaled = scaled - frac + (frac >= 0.4999 ? 1.0 : 0.0);
  return scaled / scale;
}

void TRRoundTree(TRNode *node, TRFloat parentAbsX, TRFloat parentAbsY, TRFloat scale)
{
  TRRect r = node->_rawFrame;
  TRFloat absX = parentAbsX + r.x, absY = parentAbsY + r.y;
  if (scale <= 0)
    node->_frame = r;
  else
    {
      BOOL text = (node->_measure != nil);
      BOOL fracW = fabs(fmod(r.width * scale, 1.0)) > 0.0001 && fabs(fmod(r.width * scale, 1.0) - 1.0) > 0.0001;
      BOOL fracH = fabs(fmod(r.height * scale, 1.0)) > 0.0001 && fabs(fmod(r.height * scale, 1.0) - 1.0) > 0.0001;
      TRRect f;
      f.x = TRRoundToGrid(r.x, scale, NO, text);
      f.y = TRRoundToGrid(r.y, scale, NO, text);
      f.width = TRRoundToGrid(absX + r.width, scale, text && fracW, text && !fracW)
              - TRRoundToGrid(absX, scale, NO, text);
      f.height = TRRoundToGrid(absY + r.height, scale, text && fracH, text && !fracH)
               - TRRoundToGrid(absY, scale, NO, text);
      node->_frame = f;
    }
  for (TRNode *c in node->_children)
    TRRoundTree(c, absX, absY, scale);
}
