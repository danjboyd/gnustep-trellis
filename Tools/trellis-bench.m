/* trellis-bench - layout performance on a synthetic screen.

   Builds a ~500-node tree (cards in a wrapping row, each a column of
   rows with text leaves), then measures a first layout and a simulated
   live resize (one relayout per width step), and counts measure-function
   calls to show how well the cache works.

   trellis-bench --virtual N: the window engine (TRVirtualLayout) over N
   items, as a list and as an auto-fill grid with group headers: the
   first layout, one scroll step per viewport (each newly realized item
   measured by laying out its own small tree), the peak RSS, and, for
   comparison, laying out all N items as one ordinary tree.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <Foundation/Foundation.h>
#import "TRNode.h"
#import "TRVirtualLayout.h"
#include <time.h>
#include <sys/resource.h>

static long gMeasures = 0;

static double now(void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec / 1e9;
}

static TRNode *TextLeaf(NSString *text)
{
  TRNode *n = [TRNode nodeWithStyle: @"flex: 1 1 auto"];
  NSUInteger len = [text length];
  n.measureBlock = ^TRSize(TRSize avail, TRMeasureMode wm, TRMeasureMode hm) {
    gMeasures++;
    double cw = 7, lh = 16, full = len * cw;
    if (wm == TRMeasureModeUndefined || avail.width >= full) return TRSizeMake(full, lh);
    double w = MAX(avail.width, 8 * cw);
    return TRSizeMake(w, ceil(full / w) * lh);
  };
  return n;
}

static long PeakRSSKiB(void)
{
  struct rusage ru;
  getrusage(RUSAGE_SELF, &ru);
#ifdef __APPLE__
  return ru.ru_maxrss / 1024;   /* bytes there */
#else
  return ru.ru_maxrss;
#endif
}

/* One item's own tree (a row: title that may wrap, a meta line). */
static TRNode *ItemTree(NSInteger i)
{
  TRNode *row = [TRNode nodeWithStyle: @"flex-direction: column; gap: 2px; padding: 6px 8px"];
  [row addChild: TextLeaf((i % 7 == 3)
    ? @"A longer title that wraps onto a second line at most widths of the list"
    : @"Short title")];
  [row addChild: TextLeaf(@"meta line")];
  return row;
}

static void BenchVirtual(TRVirtualMode mode, NSInteger n)
{
  double t0 = now();
  TRVirtualLayout *L = [[TRVirtualLayout alloc] initWithMode: mode];
  if (mode == TRVirtualModeGrid)
    {
      [L setContainerDeclarations: @"grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 10px; padding: 12px" error: NULL];
      L.spansFullRow = ^BOOL (NSInteger i) { return i % 40 == 0; };
      L.estimatedSize = 90;
    }
  else
    {
      [L setContainerDeclarations: @"gap: 4px; padding: 6px" error: NULL];
      L.estimatedSize = 44;
    }
  L.width = 1200;
  L.itemCount = n;
  TRFloat viewport = 800;
  __block NSInteger measured = 0;
  void (^realize)(NSRange) = ^(NSRange r) {
    for (NSUInteger i = r.location; i < NSMaxRange(r); i++)
      {
        if ([L isMeasured: (NSInteger)i]) continue;
        @autoreleasepool {
        TRNode *t = ItemTree((NSInteger)i);
        [t layoutWithAvailableSize: TRSizeMake([L widthForItem: (NSInteger)i], NAN)];
        [L setMeasuredHeight: t.layoutFrame.height forItem: (NSInteger)i];
        measured++;
        }
      }
  };
  realize([L itemsForViewportOffset: 0 height: viewport overscan: 1]);
  double t1 = now();
  NSInteger firstMeasured = measured;
  int steps = 0;
  double worst = 0;
  TRFloat y = 0;
  while (y + viewport < L.contentHeight)
    {
      double s0 = now();
      y += viewport;
      TRVirtualAnchor a = [L anchorForOffset: y];
      realize([L itemsForViewportOffset: y height: viewport overscan: 1]);
      y = [L offsetForAnchor: a];
      double s1 = now();
      if (s1 - s0 > worst) worst = s1 - s0;
      steps++;
    }
  double t2 = now();
  printf("%s, %ld items: first layout %.2f ms (%ld measured); %d scroll steps, %.3f ms/step avg, %.3f ms worst; "
         "content %.0f px, %ld columns\n",
         mode == TRVirtualModeGrid ? "grid" : "list", (long)n, (t1 - t0) * 1000, (long)firstMeasured, steps,
         steps ? (t2 - t1) * 1000 / steps : 0, worst * 1000, L.contentHeight, (long)L.columnCount);
}

static void BenchFullTree(NSInteger n)
{
  double t0 = now();
  TRNode *root = [TRNode nodeWithStyle: @"flex-direction: column; gap: 4px; padding: 6px"];
  for (NSInteger i = 0; i < n; i++) [root addChild: ItemTree(i)];
  double t1 = now();
  [root layoutWithAvailableSize: TRSizeMake(1200, NAN)];
  double t2 = now();
  printf("for comparison, one tree of %ld items: build %.1f ms, first layout %.1f ms\n",
         (long)n, (t1 - t0) * 1000, (t2 - t1) * 1000);
}

int main(int argc, const char **argv)
{
  @autoreleasepool
    {
      if (argc > 1 && strcmp(argv[1], "--virtual") == 0)
        {
          NSInteger n = argc > 2 ? atol(argv[2]) : 10000;
          long rss0 = PeakRSSKiB();
          BenchVirtual(TRVirtualModeList, n);
          BenchVirtual(TRVirtualModeGrid, n);
          long rss1 = PeakRSSKiB();
          printf("peak RSS: %ld KiB before, %ld KiB after the virtual runs\n", rss0, rss1);
          BenchFullTree(n);
          printf("peak RSS after the full tree: %ld KiB\n", PeakRSSKiB());
          printf("budget at 60 Hz: 16.7 ms/frame\n");
          return 0;
        }
      int cards = argc > 1 ? atoi(argv[1]) : 40;
      TRNode *root = [TRNode nodeWithStyle: @"flex-direction: row; flex-wrap: wrap; gap: 8px; padding: 12px; align-content: flex-start"];
      NSInteger nodes = 1;
      for (int c = 0; c < cards; c++)
        {
          TRNode *card = [TRNode nodeWithStyle: @"flex: 1 1 220px; flex-direction: column; gap: 4px; padding: 8px; border: 1px"];
          [root addChild: card]; nodes++;
          for (int r = 0; r < 4; r++)
            {
              TRNode *row = [TRNode nodeWithStyle: @"flex-direction: row; gap: 6px; align-items: baseline"];
              [card addChild: row]; nodes++;
              [row addChild: TextLeaf(@"Label")]; nodes++;
              [row addChild: TextLeaf(@"Some value text that may wrap at narrow widths")]; nodes++;
            }
        }
      double t0 = now();
      [root layoutWithAvailableSize: TRSizeMake(1200, NAN)];
      double t1 = now();
      long firstMeasures = gMeasures;
      gMeasures = 0;
      int steps = 0;
      for (double w = 1200; w >= 400; w -= 4, steps++)
        [root layoutWithAvailableSize: TRSizeMake(w, NAN)];
      double t2 = now();
      long resizeMeasures = gMeasures;
      gMeasures = 0;
      for (double w = 400; w <= 1200; w += 4)
        [root layoutWithAvailableSize: TRSizeMake(w, NAN)];
      double t3 = now();
      printf("nodes: %ld\n", (long)nodes);
      printf("first layout: %.2f ms, %ld measure calls\n", (t1 - t0) * 1000, firstMeasures);
      printf("resize (%d steps, 1200->400): %.3f ms/step, %.1f measure calls/step\n",
             steps, (t2 - t1) * 1000 / steps, (double)resizeMeasures / steps);
      printf("resize back (400->1200): %.3f ms/step, %.1f measure calls/step\n",
             (t3 - t2) * 1000 / steps, (double)gMeasures / steps);
      printf("budget at 60 Hz: 16.7 ms/frame\n");
    }
  return 0;
}
