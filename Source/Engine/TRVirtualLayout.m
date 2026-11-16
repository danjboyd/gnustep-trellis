/* TRVirtualLayout.m - the window engine for virtualized lists and grids.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRVirtualLayout.h"
#import "TRNode.h"
#import "TRStyle.h"

typedef struct {
  NSInteger first, count;
  TRFloat top, height;
} TRVRow;

@implementation TRVirtualLayout
{
  TRVirtualMode _mode;
  NSString *_decls;
  TRFloat _width;
  NSInteger _count;
  NSMutableData *_heights;        /* TRFloat per item; NAN = never measured */
  NSMutableData *_measured;       /* BOOL per item: measured at this width */
  /* Derived (valid while !_dirtyColumns / !_dirtyRows) */
  BOOL _dirtyColumns, _dirtyRows;
  NSInteger _dirtyTopsFrom;       /* first row whose top is stale; NSNotFound = none */
  NSMutableData *_colX, *_colW;   /* TRFloat per column */
  NSInteger _cols;
  TRFloat _padTop, _padBottom, _rowGap;
  NSMutableData *_rows;           /* TRVRow */
  NSInteger _rowCount;
  TRFloat _content;
}

- (instancetype)initWithMode:(TRVirtualMode)mode
{
  if ((self = [super init]) != nil)
    {
      _mode = mode;
      _decls = @"";
      _estimatedSize = 44;
      _heights = [NSMutableData data];
      _measured = [NSMutableData data];
      _colX = [NSMutableData data];
      _colW = [NSMutableData data];
      _rows = [NSMutableData data];
      _dirtyColumns = _dirtyRows = YES;
      _dirtyTopsFrom = NSNotFound;
    }
  return self;
}

- (instancetype)init
{
  return [self initWithMode: TRVirtualModeList];
}

- (TRVirtualMode)mode { return _mode; }

- (BOOL)setContainerDeclarations:(NSString *)declarations error:(NSError **)error
{
  NSString *d = declarations ?: @"";
  TRStyle *probe = [TRStyle new];
  if (![probe applyDeclarations: d error: error]) return NO;
  _decls = [d copy];
  _dirtyColumns = _dirtyRows = YES;
  return YES;
}

- (TRFloat)width { return _width; }
- (void)setWidth:(TRFloat)width
{
  if (width == _width) return;
  _width = width;
  _dirtyColumns = _dirtyRows = YES;
  /* Heights measured at the old width stay, as estimates. */
  memset([_measured mutableBytes], 0, [_measured length]);
}

- (NSInteger)itemCount { return _count; }
- (void)setItemCount:(NSInteger)count
{
  if (count < 0) count = 0;
  [_heights setLength: (NSUInteger)count * sizeof(TRFloat)];
  [_measured setLength: (NSUInteger)count];
  TRFloat *h = [_heights mutableBytes];
  for (NSInteger i = _count; i < count; i++) h[i] = NAN;
  _count = count;
  _dirtyRows = YES;
}

- (void)setEstimatedSize:(TRFloat)size { _estimatedSize = size; _dirtyRows = YES; }
- (void)setSpansFullRow:(BOOL (^)(NSInteger))b { _spansFullRow = [b copy]; _dirtyRows = YES; }
- (void)setEstimateForItem:(TRFloat (^)(NSInteger))b { _estimateForItem = [b copy]; _dirtyRows = YES; }

- (void)setMeasuredHeight:(TRFloat)height forItem:(NSInteger)item
{
  if (item < 0 || item >= _count) return;
  TRFloat *h = [_heights mutableBytes];
  BOOL *m = [_measured mutableBytes];
  if (m[item] && h[item] == height) return;
  TRFloat old = [self heightOfItem: item];
  h[item] = height;
  m[item] = YES;
  if (old == height) return;
  if (_dirtyRows || _dirtyColumns) { _dirtyRows = YES; return; }
  /* Only heights changed: fix this row, and tops from here on lazily. */
  NSInteger r = [self rowOfItem: item];
  TRVRow *row = &((TRVRow *)[_rows mutableBytes])[r];
  TRFloat rh = 0;
  for (NSInteger i = row->first; i < row->first + row->count; i++) rh = MAX(rh, [self heightOfItem: i]);
  if (rh == row->height) return;
  row->height = rh;
  if (_dirtyTopsFrom == NSNotFound || r < _dirtyTopsFrom) _dirtyTopsFrom = r;
}

- (BOOL)isMeasured:(NSInteger)item
{
  return item >= 0 && item < _count && ((const BOOL *)[_measured bytes])[item];
}

- (void)forgetMeasuredHeights
{
  TRFloat *h = [_heights mutableBytes];
  for (NSInteger i = 0; i < _count; i++) h[i] = NAN;
  memset([_measured mutableBytes], 0, [_measured length]);
  _dirtyRows = YES;
}

- (void)insertItemsAtIndex:(NSInteger)index count:(NSInteger)n
{
  if (n <= 0) return;
  index = MAX(0, MIN(index, _count));
  NSMutableData *nh = [NSMutableData dataWithLength: (NSUInteger)n * sizeof(TRFloat)];
  TRFloat *p = [nh mutableBytes];
  for (NSInteger i = 0; i < n; i++) p[i] = NAN;
  [_heights replaceBytesInRange: NSMakeRange((NSUInteger)index * sizeof(TRFloat), 0)
                      withBytes: p length: [nh length]];
  NSMutableData *nm = [NSMutableData dataWithLength: (NSUInteger)n];
  [_measured replaceBytesInRange: NSMakeRange((NSUInteger)index, 0) withBytes: [nm bytes] length: (NSUInteger)n];
  _count += n;
  _dirtyRows = YES;
}

- (void)removeItemsAtIndex:(NSInteger)index count:(NSInteger)n
{
  if (index < 0 || index >= _count || n <= 0) return;
  n = MIN(n, _count - index);
  [_heights replaceBytesInRange: NSMakeRange((NSUInteger)index * sizeof(TRFloat), (NSUInteger)n * sizeof(TRFloat))
                      withBytes: NULL length: 0];
  [_measured replaceBytesInRange: NSMakeRange((NSUInteger)index, (NSUInteger)n) withBytes: NULL length: 0];
  _count -= n;
  _dirtyRows = YES;
}

/* ---- Derived layout ---- */

/* Columns, padding and row gap, from the real engine: a probe container
   with the given style and a few 1px items. */
- (void)resolveColumns
{
  if (!_dirtyColumns) return;
  _dirtyColumns = NO;
  BOOL grid = (_mode == TRVirtualModeGrid);
  NSString *base = grid ? @"display: grid; " : @"display: flex; flex-direction: column; ";
  TRNode *root = [TRNode nodeWithStyle: [base stringByAppendingString: _decls]];
  /* The probe's own height must come from its items. */
  [root.style applyDeclarations: @"height: auto; min-height: 0; max-height: none" error: NULL];
  NSInteger k = grid ? 64 : 2;
  for (NSInteger i = 0; i < k; i++)
    [root addChild: [TRNode nodeWithStyle: grid ? @"height: 1px" : @"height: 1px; flex: none"]];
  [root layoutWithAvailableSize: TRSizeMake(_width, NAN)];
  NSArray<TRNode *> *kids = root.children;
  TRRect f0 = kids[0].layoutFrame;
  [_colX setLength: 0];
  [_colW setLength: 0];
  NSInteger cols = 0;
  TRFloat nextRowY = NAN;
  for (TRNode *c in kids)
    {
      TRRect f = c.layoutFrame;
      if (f.y != f0.y) { nextRowY = f.y; break; }
      [_colX appendBytes: &f.x length: sizeof(TRFloat)];
      [_colW appendBytes: &f.width length: sizeof(TRFloat)];
      cols++;
    }
  if (!grid) { cols = 1; [_colX setLength: sizeof(TRFloat)]; [_colW setLength: sizeof(TRFloat)]; }
  _cols = MAX(cols, 1);
  _padTop = f0.y;
  if (grid)
    _rowGap = isnan(nextRowY) ? 0 : nextRowY - (f0.y + 1);
  else
    _rowGap = kids[1].layoutFrame.y - (f0.y + 1);
  TRRect last = [kids lastObject].layoutFrame;
  _padBottom = root.layoutFrame.height - (last.y + last.height);
  _dirtyRows = YES;
}

- (TRFloat)heightOfItem:(NSInteger)i
{
  TRFloat h = ((const TRFloat *)[_heights bytes])[i];
  if (!isnan(h)) return h;
  if (_estimateForItem) return _estimateForItem(i);
  return _estimatedSize;
}

/* Recomputes row tops (and the content height) from the first stale row. */
- (void)resolveTops
{
  if (_dirtyTopsFrom == NSNotFound) return;
  TRVRow *rows = [_rows mutableBytes];
  NSInteger from = _dirtyTopsFrom;
  _dirtyTopsFrom = NSNotFound;
  TRFloat y = from > 0 ? rows[from - 1].top + rows[from - 1].height + _rowGap : _padTop;
  for (NSInteger r = from; r < _rowCount; r++)
    {
      rows[r].top = y;
      y += rows[r].height + _rowGap;
    }
  if (_rowCount > 0) y -= _rowGap;
  _content = y + _padBottom;
}

- (void)resolveRows
{
  [self resolveColumns];
  if (!_dirtyRows) { [self resolveTops]; return; }
  _dirtyRows = NO;
  _dirtyTopsFrom = NSNotFound;
  BOOL grid = (_mode == TRVirtualModeGrid);
  NSInteger cols = grid ? _cols : 1;
  [_rows setLength: 0];
  _rowCount = 0;
  TRFloat y = _padTop;
  NSInteger i = 0;
  while (i < _count)
    {
      TRVRow r = { i, 0, y, 0 };
      if (grid && _spansFullRow && _spansFullRow(i))
        {
          r.count = 1;
          r.height = [self heightOfItem: i];
          i++;
        }
      else
        {
          while (i < _count && r.count < cols && !(grid && _spansFullRow && _spansFullRow(i)))
            {
              r.height = MAX(r.height, [self heightOfItem: i]);
              r.count++;
              i++;
            }
        }
      [_rows appendBytes: &r length: sizeof r];
      _rowCount++;
      y += r.height + _rowGap;
    }
  if (_rowCount > 0) y -= _rowGap;
  _content = y + _padBottom;
}

- (TRFloat)contentHeight { [self resolveRows]; return _content; }
- (NSInteger)columnCount { [self resolveColumns]; return _mode == TRVirtualModeGrid ? _cols : 1; }

/* The row holding an item (binary search on first). */
- (NSInteger)rowOfItem:(NSInteger)item
{
  const TRVRow *rows = [_rows bytes];
  NSInteger lo = 0, hi = _rowCount - 1;
  while (lo < hi)
    {
      NSInteger mid = (lo + hi + 1) / 2;
      if (rows[mid].first <= item) lo = mid; else hi = mid - 1;
    }
  return lo;
}

/* The first row whose bottom (gap included) is below y. */
- (NSInteger)rowAtOffset:(TRFloat)y
{
  const TRVRow *rows = [_rows bytes];
  NSInteger lo = 0, hi = _rowCount - 1;
  while (lo < hi)
    {
      NSInteger mid = (lo + hi) / 2;
      if (rows[mid].top + rows[mid].height + _rowGap > y) hi = mid; else lo = mid + 1;
    }
  return lo;
}

- (TRFloat)widthForItem:(NSInteger)item
{
  [self resolveColumns];
  if (item < 0 || item >= _count) return 0;
  const TRFloat *cx = [_colX bytes], *cw = [_colW bytes];
  if (_mode != TRVirtualModeGrid) return cw[0];
  if (_spansFullRow && _spansFullRow(item)) return cx[_cols - 1] + cw[_cols - 1] - cx[0];
  /* Equal columns (auto-fill, repeat(n, 1fr)) need no rows. */
  BOOL equal = YES;
  for (NSInteger c = 1; c < _cols; c++) if (fabs(cw[c] - cw[0]) > 0.01) { equal = NO; break; }
  return equal ? cw[0] : [self frameForItem: item].width;
}

- (TRFloat)heightForItem:(NSInteger)item
{
  return (item >= 0 && item < _count) ? [self heightOfItem: item] : 0;
}

- (TRRect)frameForItem:(NSInteger)item
{
  [self resolveRows];
  if (item < 0 || item >= _count) return (TRRect){ 0, 0, 0, 0 };
  const TRVRow *r = &((const TRVRow *)[_rows bytes])[[self rowOfItem: item]];
  const TRFloat *cx = [_colX bytes], *cw = [_colW bytes];
  NSInteger cols = (_mode == TRVirtualModeGrid) ? _cols : 1;
  BOOL full = (_mode == TRVirtualModeGrid && _spansFullRow && _spansFullRow(item));
  if (full)
    return (TRRect){ cx[0], r->top, cx[cols - 1] + cw[cols - 1] - cx[0], r->height };
  NSInteger c = item - r->first;
  return (TRRect){ cx[c], r->top, cw[c], r->height };
}

- (NSInteger)rowForItem:(NSInteger)item column:(NSInteger *)column
{
  [self resolveRows];
  if (item < 0 || item >= _count) { if (column) *column = 0; return NSNotFound; }
  NSInteger r = [self rowOfItem: item];
  if (column) *column = item - ((const TRVRow *)[_rows bytes])[r].first;
  return r;
}

- (NSRange)itemsForViewportOffset:(TRFloat)offset height:(TRFloat)height overscan:(TRFloat)viewports
{
  [self resolveRows];
  if (_rowCount == 0) return NSMakeRange(0, 0);
  TRFloat lo = offset - viewports * height, hi = offset + height + viewports * height;
  NSInteger a = [self rowAtOffset: MAX(lo, 0)];
  NSInteger b = [self rowAtOffset: hi];
  const TRVRow *rows = [_rows bytes];
  if (rows[b].top >= hi && b > a) b--;
  NSInteger first = rows[a].first, end = rows[b].first + rows[b].count;
  return NSMakeRange((NSUInteger)first, (NSUInteger)(end - first));
}

/* ---- Anchoring ---- */

- (TRVirtualAnchor)anchorForOffset:(TRFloat)offset
{
  [self resolveRows];
  if (_rowCount == 0) return (TRVirtualAnchor){ NSNotFound, 0 };
  const TRVRow *r = &((const TRVRow *)[_rows bytes])[[self rowAtOffset: offset]];
  return (TRVirtualAnchor){ r->first, offset - r->top };
}

- (TRFloat)offsetForAnchor:(TRVirtualAnchor)anchor
{
  [self resolveRows];
  if (anchor.item == NSNotFound || _rowCount == 0) return 0;
  NSInteger item = MIN(MAX(anchor.item, 0), _count - 1);
  const TRVRow *r = &((const TRVRow *)[_rows bytes])[[self rowOfItem: item]];
  return MAX(r->top + anchor.delta, 0);
}

- (TRVirtualAnchor)anchor:(TRVirtualAnchor)a afterInsertAt:(NSInteger)index count:(NSInteger)n
{
  if (a.item != NSNotFound && a.item >= index) a.item += n;
  return a;
}

- (TRVirtualAnchor)anchor:(TRVirtualAnchor)a afterRemoveAt:(NSInteger)index count:(NSInteger)n
{
  if (a.item == NSNotFound) return a;
  if (a.item >= index + n) a.item -= n;
  else if (a.item >= index) { a.item = index; a.delta = 0; }
  return a;
}

@end
