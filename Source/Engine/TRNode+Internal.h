/* TRNode+Internal.h - engine-private state of TRNode.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRNode.h"

#define TR_CACHE_SIZE 16

typedef struct {
  TRFloat aw, ah;
  TRMeasureMode wm, hm;
  TRFloat ow, oh;
  TRDirection dir;
  BOOL indefH;                   /* the node's _pctIndefH at the time */
  TRSize result;
} TRCacheEntry;

@interface TRNode ()
{
@public
  TRStyle *_style;
  NSMutableArray<TRNode *> *_children;
  __weak TRNode *_parent;
  __weak TRNode *_cqParent;      /* containerQueryParent */
  TRMeasureBlock _measure;
  TRBaselineBlock _baselineFn;
  BOOL _dirty;
  BOOL _hidden;                  /* like display: none, independent of the style */
  /* Set by a flex parent: this node's height is not definite (css-flexbox
     9.8), so its children's percentage heights act as auto even when it
     is laid out at an exact height. */
  BOOL _pctIndefH;
  /* The node -layoutWithAvailableSize: was called on: a containing block
     for abspos descendants even when it is position: static. */
  BOOL _isLayoutRoot;

  /* Results. _rawFrame is unrounded; _frame is what clients see. */
  TRRect _rawFrame;
  TRRect _frame;
  TRFloat _lpad[4], _lborder[4], _lmargin[4];
  TRDirection _ldir;
  TRSize _contentSize;
  NSInteger _lineIndex;

  /* Measurement cache, cleared by -markDirty. */
  TRCacheEntry _cache[TR_CACHE_SIZE];
  int _cacheCount, _cacheNext;
  BOOL _hasPerformEntry;
  TRCacheEntry _performEntry;

  /* Container queries (TRContainerQuery.m). */
  TRStyle *_baseStyle;            /* the style without conditional overlays */
  NSMutableArray *_conditions;    /* TRCondition objects, in order */
  uint64_t _matchedMask;
}
@end

/* Out of the layout: hidden, or display: none. */
static inline BOOL TRNodeIsNone(TRNode *n)
{
  return n->_hidden || n->_style->_s.display == TRDisplayNone;
}

/* A style's storage with its logical sides (margin-inline-start and so
   on) mapped for the box's direction (TRStyle.m). */
const TRStyleStorage *TRStyleStorageForDirection(TRStyle *st, TRDirection dir);

/* A child's storage, mapped for its own direction (its direction
   property, or its parent's when that's inherit). */
static inline const TRStyleStorage *TRChildStyle(TRNode *c, TRDirection parentDir)
{
  TRDirection d = c->_style->_s.direction;
  if (d == TRDirectionInherit) d = parentDir;
  return TRStyleStorageForDirection(c->_style, d);
}

/* self-start / self-end (css-align-3): start and end in the item's own
   direction. In the inline axis an item whose direction differs from its
   container's swaps them; in the block axis they equal start and end.
   item is the item's storage (its direction field, or inherit). */
static inline TRAlign TRSelfAlignFlip(TRAlign a, BOOL isSelf, BOOL inlineAxis,
                                      const TRStyleStorage *item, TRDirection containerDir)
{
  if (!isSelf || !inlineAxis) return a;
  TRDirection d = item->direction == TRDirectionInherit ? containerDir : item->direction;
  if (d == containerDir) return a;
  return a == TRAlignStart ? TRAlignEnd : (a == TRAlignEnd ? TRAlignStart : a);
}

/* Places the abspos boxes inside cur's static descendants against a
   containing block's padding box (cbX, cbY, cbW, cbH); (ox, oy) is cur's
   origin in the containing block's border-box coordinates (TRLayout.m).
   area, when set, gives an abspos box its own containing block instead (a
   grid area, in the containing block's border-box coordinates). */
typedef void (^TRAbsAreaBlock)(TRNode *abs, TRFloat *x, TRFloat *y, TRFloat *w, TRFloat *h);
void TRLayoutStaticDescendants(TRNode *cur, TRDirection cbDir, TRFloat ox, TRFloat oy,
                               TRFloat cbX, TRFloat cbY, TRFloat cbW, TRFloat cbH,
                               TRAbsAreaBlock area);

/* The style with min-content / max-content / fit-content / stretch sizes
   measured and written as px into buf (or cs itself when it has none).
   availW/availH: the space the parent offers the margin box (NAN when
   indefinite); refW/refH: percentage bases; mainIsWidth: flex-basis axis. */
const TRStyleStorage *TRResolveSizeKeywords(TRNode *c, const TRStyleStorage *cs, TRStyleStorage *buf,
                                            TRFloat availW, TRFloat availH, TRFloat refW, TRFloat refH,
                                            BOOL mainIsWidth, TRDirection dir);

/* The layout algorithm (TRLayout.m). Returns the node's border-box size.
   aw/ah: border-box constraint, read according to wm/hm.
   ow/oh: the containing block's inner size, for percentages.
   perform: NO = measure only (no frames are written anywhere). */
TRSize TRLayoutNode(TRNode *node, TRFloat aw, TRFloat ah,
                    TRMeasureMode wm, TRMeasureMode hm,
                    TRFloat ow, TRFloat oh, BOOL perform,
                    TRDirection parentDirection);

/* Re-evaluates container queries after a layout pass; YES if any node's
   effective style changed (and so another pass is needed). */
BOOL TRApplyContainerQueries(TRNode *root);

void TRRoundTree(TRNode *node, TRFloat parentAbsX, TRFloat parentAbsY, TRFloat scale);
TRFloat TRComputeBaseline(TRNode *node);
