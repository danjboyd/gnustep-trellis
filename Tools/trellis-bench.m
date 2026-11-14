/* trellis-bench - layout performance on a synthetic screen.

   Builds a ~500-node tree (cards in a wrapping row, each a column of
   rows with text leaves), then measures a first layout and a simulated
   live resize (one relayout per width step), and counts measure-function
   calls to show how well the cache works.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <Foundation/Foundation.h>
#import "TRNode.h"
#include <time.h>

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

int main(int argc, const char **argv)
{
  @autoreleasepool
    {
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
