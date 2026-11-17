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
