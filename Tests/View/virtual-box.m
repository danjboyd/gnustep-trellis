/* TRVirtualBox checks (headless): reuse keeps the view count flat while
   scrolling 10,000 items, scroll anchoring through inserts and removals,
   Tab past the realized edge, the focused item surviving a scroll away,
   accessibility positions, a grid with full-row headers, and a box freed
   with work pending (run with NSZombieEnabled). Prints VIRTUALBOX OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"
#import "TRVirtualBox.h"
#include <signal.h>
#include <unistd.h>

static NSString *const kSpec =
  @"<column id=\"root\">\n"
  @"  <button id=\"before\">Before</button>\n"
  @"  <virtual id=\"list\" template=\"row\" estimated-size=\"30\">\n"
  @"    <template id=\"row\"><row class=\"row\"><text id=\"t\"/><button id=\"b\">Open</button></row></template>\n"
  @"  </virtual>\n"
  @"  <button id=\"after\">After</button>\n"
  @"  <style>\n"
  @"    #list { gap: 4px; padding: 6px; }\n"
  @"    .row { gap: 8px; align-items: flex-start; }\n"
  @"    #t { flex: 1; }\n"
  @"  </style>\n"
  @"</column>\n";

static NSString *const kGrid =
  @"<column>\n"
  @"  <virtual id=\"wall\" layout=\"grid\" template=\"tile\" estimated-size=\"60\">\n"
  @"    <template id=\"tile\"><column class=\"tile\"><label id=\"name\"/><label id=\"state\"/></column></template>\n"
  @"    <template id=\"group\"><label class=\"group\" id=\"title\"/></template>\n"
  @"  </virtual>\n"
  @"  <style>\n"
  @"    #wall { grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 10px; padding: 12px; }\n"
  @"    .group { grid-column: 1 / -1; font-weight: bold; }\n"
  @"    .tile { padding: 6px; gap: 2px; }\n"
  @"  </style>\n"
  @"</column>\n";

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  fflush(stdout);
  if (!ok) gFail++;
}

static void OnAlarm(int sig)
{
  (void)sig;
  static const char m[] = "FAIL hung (alarm)\nVIRTUALBOX FAIL\n";
  write(1, m, sizeof m - 1);
  _exit(1);
}

static void Spin(void)
{
  for (int i = 0; i < 3; i++)
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.005]];
}

@interface ListData : NSObject <TRVirtualDataSource>
{
@public
  NSInteger count;
  NSInteger configured;
}
@end
@implementation ListData
- (NSInteger)numberOfItemsInVirtualBox:(TRVirtualBox *)box { return count; }
- (void)virtualBox:(TRVirtualBox *)box configureView:(NSView *)view atIndex:(NSInteger)i
{
  configured++;
  NSTextField *t = (NSTextField *)[TRLoader viewWithIdentifier: @"t" inView: view];
  /* Every seventh row is long and wraps to several lines. */
  NSString *s = (i % 7 == 3)
    ? [NSString stringWithFormat: @"Row %ld: a longer note that wraps onto more than one line at this width, so it is taller than the estimate", (long)i]
    : [NSString stringWithFormat: @"Row %ld", (long)i];
  [t setStringValue: s];
}
@end

@interface GridData : NSObject <TRVirtualDataSource>
@end
@implementation GridData
- (NSInteger)numberOfItemsInVirtualBox:(TRVirtualBox *)box { return 2000; }
- (NSString *)virtualBox:(TRVirtualBox *)box templateForItemAtIndex:(NSInteger)i
{
  return (i % 25 == 0) ? @"group" : @"tile";
}
- (void)virtualBox:(TRVirtualBox *)box configureView:(NSView *)view atIndex:(NSInteger)i
{
  if (i % 25 == 0)
    [(NSTextField *)[TRLoader viewWithIdentifier: @"title" inView: view]
      setStringValue: [NSString stringWithFormat: @"Group %ld", (long)(i / 25)]];
  else
    {
      [(NSTextField *)[TRLoader viewWithIdentifier: @"name" inView: view]
        setStringValue: [NSString stringWithFormat: @"agent-%04ld", (long)i]];
      [(NSTextField *)[TRLoader viewWithIdentifier: @"state" inView: view] setStringValue: @"Working"];
    }
}
@end

static CGFloat Offset(TRVirtualBox *b) { return [[b contentView] bounds].origin.y; }
static void ScrollTo(TRVirtualBox *b, CGFloat y)
{
  [[b contentView] scrollToPoint: NSMakePoint(0, y)];
  [b reflectScrolledClipView: [b contentView]];
}

static NSView *LogicalFocus(NSWindow *w)
{
  NSResponder *r = [w firstResponder];
  if ([r isKindOfClass: [NSText class]] && [(NSText *)r isFieldEditor]) r = (NSResponder *)[(NSText *)r delegate];
  return [r isKindOfClass: [NSView class]] ? (NSView *)r : nil;
}

int main(void)
{
  @autoreleasepool
    {
#ifdef GNUSTEP
      [NSApplication sharedApplication];
#endif
      signal(SIGALRM, OnAlarm);
      alarm(60);
      NSError *err = nil;
      TRMarkupDocument *doc = [TRMarkupDocument documentWithString: kSpec name: @"virtual.trellis" error: &err];
      TRBoxView *root = doc ? [TRLoader loadDocument: doc owner: nil error: &err] : nil;
      if (root == nil) { printf("load failed: %s\n", [[err localizedDescription] UTF8String]); return 2; }
      TRVirtualBox *box = (TRVirtualBox *)[TRLoader viewWithIdentifier: @"list" inView: root];
      Expect("<virtual> builds a TRVirtualBox", [box isKindOfClass: [TRVirtualBox class]]);
      NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 400, 300)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered defer: YES];
      [win setReleasedWhenClosed: NO];
      [win setContentView: root];
      ListData *data = [ListData new];
      data->count = 10000;
      box.dataSource = data;
      [root layoutTrellis];
      [box updateVirtualContent];

      TRVirtualLayout *L = box.virtualLayout;
      NSUInteger realized = [box.realizedIndexes count];
      printf("     box %.0fx%.0f, realized %lu, content %.0f\n", [box frame].size.width, [box frame].size.height,
             (unsigned long)realized, L.contentHeight);
      Expect("some items realized", realized > 0);
      Expect("only a few hundred px worth realized", realized < 60);
      Expect("item 0 is realized at the top", [box viewForItemAtIndex: 0] != nil && Offset(box) == 0);
      Expect("item 3 (long) measured taller than the estimate", [L frameForItem: 3].height > 30);

      /* Reuse: scroll through everything a viewport at a time. */
      NSUInteger maxLive = 0, steps = 0;
      NSInteger configuredBefore = data->configured;
      CGFloat vh = [box contentSize].height;
      while (Offset(box) + vh < L.contentHeight - 1 && steps < 5000)
        {
          ScrollTo(box, Offset(box) + vh);
          NSUInteger live = [box.realizedIndexes count] + box.pooledViewCount;
          if (live > maxLive) maxLive = live;
          steps++;
        }
      printf("     %lu steps, at most %lu views alive, %ld configures\n", (unsigned long)steps,
             (unsigned long)maxLive, (long)(data->configured - configuredBefore));
      Expect("reached the end", [box viewForItemAtIndex: 9999] != nil);
      Expect("views alive stay flat (< 120) over 10,000 items", maxLive < 120);
      Expect("all items measured by the end", [L isMeasured: 9999] && [L isMeasured: 5000]);

      /* Anchoring: insert above the viewport; the top item doesn't move. */
      [box scrollToItemAtIndex: 5000 position: TRVirtualScrollTop];
      CGFloat before = [[box viewForItemAtIndex: 5000] frame].origin.y - Offset(box);
      [box insertItemsAtIndexes: [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(10, 10)]];
      data->count += 10;
      NSView *moved = [box viewForItemAtIndex: 5010];
      CGFloat after = moved ? [moved frame].origin.y - Offset(box) : -9999;
      printf("     anchor: %.1f before, %.1f after insert\n", before, after);
      Expect("insert above keeps the anchored item still", moved != nil && fabs(after - before) < 0.5);
      [box removeItemsAtIndexes: [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(100, 50)]];
      data->count -= 50;
      moved = [box viewForItemAtIndex: 4960];
      after = moved ? [moved frame].origin.y - Offset(box) : -9999;
      Expect("removal above keeps the anchored item still", moved != nil && fabs(after - before) < 0.5);

      /* At the very top, inserts at 0 push content down (no anchoring). */
      ScrollTo(box, 0);
      [box insertItemsAtIndexes: [NSIndexSet indexSetWithIndex: 0]];
      data->count += 1;
      Expect("at the top, the view stays at the top", Offset(box) == 0);

      /* Accessibility. */
      NSInteger n = 0, cols = -1, idx = -1, row = -1, col = -1;
      Expect("role list", [TRAccessibilityRole(box) isEqualToString: @"list"]);
      Expect("collection count is the full count",
             TRAccessibilityCollection(box, &n, &cols) && n == data->count && cols == 0);
      Expect("item records its index", TRAccessibilityPosition([box viewForItemAtIndex: 2], &idx, &row, &col) && idx == 2);

      /* Keyboard: Tab from Before walks into the list and past its edge. */
      [win makeFirstResponder: [TRLoader viewWithIdentifier: @"before" inView: root]];
      NSInteger lastVisible = (NSInteger)NSMaxRange(box.visibleRange) - 1, reached = -1;
      for (int i = 0; i < 40; i++)
        {
          [win selectKeyViewFollowingView: LogicalFocus(win)];
          Spin();
          NSInteger k = [box indexOfItemView: LogicalFocus(win)];
          if (getenv("VB_DEBUG")) printf("     tab %d: %s item %ld off %.0f\n", i, [NSStringFromClass([LogicalFocus(win) class]) UTF8String], (long)k, Offset(box));
          if (k != NSNotFound && k > reached) reached = k;
        }
      printf("     tab: last visible was %ld, reached %ld, offset %.0f\n", (long)lastVisible, (long)reached, Offset(box));
      Expect("Tab reaches items past the first screen", reached > lastVisible);
      Expect("the list scrolled to follow focus", Offset(box) > 0);
      NSInteger fi = [box indexOfItemView: LogicalFocus(win)];
      Expect("the focused item is visible", fi != NSNotFound && NSLocationInRange((NSUInteger)fi, box.visibleRange));

      /* Shift-Tab back from the first visible item scrolls up. */
      [box scrollToItemAtIndex: 300 position: TRVirtualScrollTop];
      [box focusItemAtIndex: (NSInteger)box.visibleRange.location last: NO];
      NSInteger startIdx = [box indexOfItemView: LogicalFocus(win)], minIdx = startIdx;
      for (int i = 0; i < 6; i++)
        {
          [win selectKeyViewPrecedingView: LogicalFocus(win)];
          Spin();
          NSInteger k = [box indexOfItemView: LogicalFocus(win)];
          if (k != NSNotFound && k < minIdx) minIdx = k;
        }
      printf("     shift-tab: from %ld down to %ld\n", (long)startIdx, (long)minIdx);
      Expect("Shift-Tab walks back one item at a time", minIdx == startIdx - 6);

      /* The focused item survives scrolling away. */
      [box focusItemAtIndex: 20 last: YES];
      NSView *fv = [box viewForItemAtIndex: 20];
      ScrollTo(box, L.contentHeight / 2);
      Expect("focused item stays realized off screen", [box viewForItemAtIndex: 20] == fv && fv != nil);
      Expect("and still holds focus", [box indexOfItemView: LogicalFocus(win)] == 20);
      [win makeFirstResponder: nil];
      ScrollTo(box, L.contentHeight / 2 + 10);
      Expect("once focus leaves, it is recycled", [box viewForItemAtIndex: 20] == nil);

      /* Grid with full-row headers. */
      TRMarkupDocument *gdoc = [TRMarkupDocument documentWithString: kGrid name: @"wall.trellis" error: &err];
      TRBoxView *groot = gdoc ? [TRLoader loadDocument: gdoc owner: nil error: &err] : nil;
      if (groot == nil) { printf("grid load failed: %s\n", [[err localizedDescription] UTF8String]); return 2; }
      TRVirtualBox *wall = (TRVirtualBox *)[TRLoader viewWithIdentifier: @"wall" inView: groot];
      GridData *gdata = [GridData new];
      [groot setFrame: NSMakeRect(0, 0, 560, 400)];
      wall.dataSource = gdata;
      [groot layoutTrellis];
      [wall updateVirtualContent];
      TRVirtualLayout *G = wall.virtualLayout;
      printf("     grid: %ld columns, content %.0f, realized %lu\n", (long)G.columnCount, G.contentHeight,
             (unsigned long)[wall.realizedIndexes count]);
      Expect("grid resolves several columns", G.columnCount == 4);
      TRRect h0 = [G frameForItem: 0], t1 = [G frameForItem: 1], h25 = [G frameForItem: 25];
      Expect("a header spans the row", fabs(h0.width - ([wall contentSize].width - 24)) < 1);
      Expect("tiles follow on the next row", t1.y > h0.y && fabs(t1.x - 12) < 0.5);
      Expect("the next header closes its row", h25.y > [G frameForItem: 24].y && fabs(h25.x - 12) < 0.5);
      Expect("role grid with columns", TRAccessibilityCollection(wall, &n, &cols) && n == 2000 && cols == 4
             && [TRAccessibilityRole(wall) isEqualToString: @"grid"]);
      Expect("tile records row and column",
             TRAccessibilityPosition([wall viewForItemAtIndex: 6], &idx, &row, &col) && idx == 6 && row == 2 && col == 1);
      NSUInteger gmax = 0;
      for (int i = 0; i < 200; i++)
        {
          ScrollTo(wall, Offset(wall) + [wall contentSize].height / 2);
          NSUInteger live = [wall.realizedIndexes count] + wall.pooledViewCount;
          if (live > gmax) gmax = live;
        }
      Expect("grid views alive stay flat", gmax < 200);

      /* Freed with realized items and a pending sentinel forward. */
      @autoreleasepool
        {
          TRVirtualBox *tmp = [[TRVirtualBox alloc] initWithMode: TRVirtualModeList];
          [tmp registerViewFactory: ^NSView * { return [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 50, 20)]; }
                           forKind: @"item"];
          ListData *d2 = [ListData new];
          d2->count = 100;
          [tmp setFrame: NSMakeRect(0, 0, 200, 200)];
          tmp.dataSource = d2;
          [tmp updateVirtualContent];
          Expect("factory views realized", [tmp.realizedIndexes count] > 0);
          tmp = nil;
        }
      Spin();
      [win close];
    }
  printf(gFail ? "VIRTUALBOX FAIL\n" : "VIRTUALBOX OK\n");
  return gFail ? 1 : 0;
}
