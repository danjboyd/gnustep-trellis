/* Checks TRVirtualLayout (the window engine for virtualized lists and
   grids): offsets, grid columns from the real grid engine, full-row
   items, realized ranges, measured-size correction, inserts and removals
   with scroll anchoring, and 10k items. Prints VIRTUAL OK. */
#import <Foundation/Foundation.h>
#import "TRVirtualLayout.h"

static int gFail = 0;
static void Eq(const char *what, double got, double want)
{
  BOOL ok = fabs(got - want) < 0.01;
  if (!ok) { printf("FAIL %s: got %g, want %g\n", what, got, want); gFail++; }
}

int main(void)
{
  @autoreleasepool
    {
      /* ---- A list: padding 10, gap 4, items 20 (estimated) ---- */
      TRVirtualLayout *L = [[TRVirtualLayout alloc] initWithMode: TRVirtualModeList];
      [L setContainerDeclarations: @"padding: 10px; gap: 4px" error: NULL];
      L.width = 300;
      L.estimatedSize = 20;
      L.itemCount = 100;
      Eq("list content height", L.contentHeight, 10 + 100 * 20 + 99 * 4 + 10);
      TRRect f = [L frameForItem: 3];
      Eq("list item 3 y", f.y, 10 + 3 * 24);
      Eq("list item 3 x", f.x, 10);
      Eq("list item 3 width", f.width, 280);
      NSRange r = [L itemsForViewportOffset: 240 height: 100 overscan: 0];
      Eq("list visible first", r.location, 9);     /* row 9 spans 226..246 */
      Eq("list visible count", r.length, 5);       /* rows 9..13 (13 starts at 322 < 340) */
      r = [L itemsForViewportOffset: 240 height: 100 overscan: 1];
      Eq("list overscan first", r.location, 5);    /* from offset 140: row 5 spans 130..150 */
      Eq("list overscan last", NSMaxRange(r) - 1, 17);  /* to 440: row 17 starts at 418, row 18 at 442 */

      /* Measuring an item above the viewport shifts the rest; the anchor
         keeps the viewport on the same item. */
      TRVirtualAnchor a = [L anchorForOffset: 250];
      Eq("anchor item", a.item, 10);
      Eq("anchor delta", a.delta, 250 - (10 + 10 * 24));
      [L setMeasuredHeight: 60 forItem: 2];
      Eq("after measure, item 3 moves down 40", [L frameForItem: 3].y, 10 + 3 * 24 + 40);
      Eq("anchored offset follows", [L offsetForAnchor: a], 250 + 40);

      /* Insert 5 above the anchor: the anchor moves with its item. */
      a = [L anchor: a afterInsertAt: 0 count: 5];
      [L insertItemsAtIndex: 0 count: 5];
      Eq("insert: count", L.itemCount, 105);
      Eq("insert: anchor item", a.item, 15);
      Eq("insert: anchored offset", [L offsetForAnchor: a], 250 + 40 + 5 * 24);
      Eq("insert: measured size moved with its item", [L frameForItem: 7].height, 60);

      /* Remove a run holding the anchor: it moves to the next survivor. */
      a = [L anchor: a afterRemoveAt: 12 count: 5];
      [L removeItemsAtIndex: 12 count: 5];
      Eq("remove: anchor item", a.item, 12);
      Eq("remove: anchor delta reset", a.delta, 0);

      /* ---- A grid: auto-fill columns of at least 100px, gap 10, padding 12,
         with full-row group headers every 10 items ---- */
      TRVirtualLayout *G = [[TRVirtualLayout alloc] initWithMode: TRVirtualModeGrid];
      [G setContainerDeclarations: @"grid-template-columns: repeat(auto-fill, minmax(100px, 1fr)); gap: 10px; padding: 12px" error: NULL];
      G.width = 354;          /* inner 330: 3 columns of 103.33 */
      G.estimatedSize = 50;
      G.spansFullRow = ^BOOL(NSInteger i) { return i % 10 == 0; };
      G.estimateForItem = ^TRFloat(NSInteger i) { return i % 10 == 0 ? 20 : 50; };
      G.itemCount = 30;
      Eq("grid columns", G.columnCount, 3);
      TRRect h0 = [G frameForItem: 0], i1 = [G frameForItem: 1], i2 = [G frameForItem: 2], i4 = [G frameForItem: 4];
      Eq("header spans the row: x", h0.x, 12);
      Eq("header spans the row: width", h0.width, 330);
      Eq("header height", h0.height, 20);
      Eq("item 1 y (after header + gap)", i1.y, 12 + 20 + 10);
      /* Column positions come from the grid engine, rounded to pixels. */
      Eq("item 2 x (second column)", i2.x, round(12 + (330 - 20) / 3.0 + 10));
      Eq("item 4 wraps to row 2", i4.y, 12 + 20 + 10 + 50 + 10);
      /* Group of 9 items = 3 rows of 3; next header starts a new row. */
      TRRect h10 = [G frameForItem: 10];
      Eq("next header y", h10.y, 12 + 20 + 10 + 3 * 60);
      [G setMeasuredHeight: 80 forItem: 5];
      Eq("tallest item sets the row height", [G frameForItem: 4].height, 80);
      Eq("grid content height", G.contentHeight, 12 + 3 * (20 + 10) + 3 * (3 * 60) - 10 + 30 + 12);
      G.width = 700;          /* inner 676: 6 columns */
      Eq("wider: more columns", G.columnCount, 6);
      Eq("wider: measured heights kept as estimates", [G frameForItem: 5].height, 80);
      Eq("wider: but not marked measured", [G isMeasured: 5], 0);

      /* ---- 10k items: build, query and update stay fast ---- */
      TRVirtualLayout *B = [[TRVirtualLayout alloc] initWithMode: TRVirtualModeGrid];
      [B setContainerDeclarations: @"grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 10px; padding: 12px" error: NULL];
      B.width = 1180;
      B.spansFullRow = ^BOOL(NSInteger i) { return i % 50 == 0; };
      B.itemCount = 10000;
      NSDate *t0 = [NSDate date];
      TRFloat ch = B.contentHeight;
      double build = -[t0 timeIntervalSinceNow] * 1000;
      t0 = [NSDate date];
      for (TRFloat y = 0; y < ch; y += 700)
        {
          NSRange w = [B itemsForViewportOffset: y height: 700 overscan: 1];
          for (NSUInteger k = w.location; k < NSMaxRange(w) && k < w.location + 4; k++)
            [B setMeasuredHeight: 110 + (k % 3) * 20 forItem: (NSInteger)k];
          (void)[B contentHeight];
        }
      double scroll = -[t0 timeIntervalSinceNow] * 1000;
      printf("10k grid: %ld columns, content %.0f px; first build %.2f ms; full scroll with remeasure %.1f ms\n",
             (long)B.columnCount, ch, build, scroll);
      if (build > 50) { printf("FAIL 10k build took %.1f ms\n", build); gFail++; }

      printf(gFail ? "VIRTUAL FAIL\n" : "VIRTUAL OK\n");
      return gFail ? 1 : 0;
    }
}
