/* TRVirtualBox with real views (headless): 10,000 items as a list and as
   an auto-fill grid in a 900x800 window. Times the first update and one
   scroll step per viewport, and reports the views alive and peak RSS.
   Fails only if the view count grows with the item count; the timings
   are for reading (headless Xvfb is not a real screen). */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"
#import "TRVirtualBox.h"
#include <time.h>
#include <sys/resource.h>

static double Now(void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec / 1e9;
}

static long PeakRSSKiB(void)
{
  struct rusage ru;
  getrusage(RUSAGE_SELF, &ru);
#ifdef __APPLE__
  return ru.ru_maxrss / 1024;
#else
  return ru.ru_maxrss;
#endif
}

static NSString *const kSpec =
  @"<column>\n"
  @"  <virtual id=\"list\" layout=\"%@\" template=\"item\" estimated-size=\"%@\">\n"
  @"    <template id=\"item\"><column class=\"item\"><text id=\"title\"/><row><label id=\"meta\"/><spacer/><button id=\"open\">Open</button></row></column></template>\n"
  @"    <template id=\"group\"><label class=\"group\" id=\"gtitle\"/></template>\n"
  @"  </virtual>\n"
  @"  <style>\n"
  @"    #list { gap: 8px; padding: 12px; %@ }\n"
  @"    .item { padding: 8px; gap: 4px; border: 1px solid -tr-separator; border-radius: 6px; }\n"
  @"    .group { grid-column: 1 / -1; font-weight: bold; }\n"
  @"  </style>\n"
  @"</column>\n";

@interface BenchData : NSObject <TRVirtualDataSource>
@end
@implementation BenchData
- (NSInteger)numberOfItemsInVirtualBox:(TRVirtualBox *)box { return 10000; }
- (NSString *)virtualBox:(TRVirtualBox *)box templateForItemAtIndex:(NSInteger)i
{
  return (box.mode == TRVirtualModeGrid && i % 40 == 0) ? @"group" : @"item";
}
- (void)virtualBox:(TRVirtualBox *)box configureView:(NSView *)v atIndex:(NSInteger)i
{
  if (box.mode == TRVirtualModeGrid && i % 40 == 0)
    {
      [(NSTextField *)[TRLoader viewWithIdentifier: @"gtitle" inView: v]
        setStringValue: [NSString stringWithFormat: @"Group %ld", (long)(i / 40)]];
      return;
    }
  [(NSTextField *)[TRLoader viewWithIdentifier: @"title" inView: v] setStringValue: (i % 7 == 3)
    ? [NSString stringWithFormat: @"Item %ld: a longer title that wraps onto a second line in a narrow slot", (long)i]
    : [NSString stringWithFormat: @"Item %ld", (long)i]];
  [(NSTextField *)[TRLoader viewWithIdentifier: @"meta" inView: v]
    setStringValue: [NSString stringWithFormat: @"updated %ld min ago", (long)(i % 59 + 1)]];
}
@end

static int Run(NSString *layout)
{
  BOOL grid = [layout isEqualToString: @"grid"];
  NSString *src = [NSString stringWithFormat: kSpec, layout, grid ? @"90" : @"60",
                   grid ? @"grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));" : @""];
  NSError *err = nil;
  TRMarkupDocument *doc = [TRMarkupDocument documentWithString: src name: @"bench.trellis" error: &err];
  TRBoxView *root = doc ? [TRLoader loadDocument: doc owner: nil error: &err] : nil;
  if (root == nil) { printf("load failed: %s\n", [[err localizedDescription] UTF8String]); return 1; }
  TRVirtualBox *box = (TRVirtualBox *)[TRLoader viewWithIdentifier: @"list" inView: root];
  NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 900, 800)
                                              styleMask: NSWindowStyleMaskTitled
                                                backing: NSBackingStoreBuffered defer: YES];
  [win setReleasedWhenClosed: NO];
  [win setContentView: root];
  [root layoutTrellis];
  BenchData *data = [BenchData new];
  double t0 = Now();
  box.dataSource = data;
  [box updateVirtualContent];
  double t1 = Now();
  CGFloat vh = [box contentSize].height;
  int steps = 0;
  double worst = 0;
  NSUInteger maxLive = 0;
  while ([[box contentView] bounds].origin.y + vh < box.virtualLayout.contentHeight - 1 && steps < 5000)
    {
      @autoreleasepool
        {
          double s0 = Now();
          [[box contentView] scrollToPoint: NSMakePoint(0, [[box contentView] bounds].origin.y + vh)];
          [box reflectScrolledClipView: [box contentView]];
          double s1 = Now();
          if (s1 - s0 > worst) worst = s1 - s0;
          NSUInteger live = [box.realizedIndexes count] + box.pooledViewCount;
          if (live > maxLive) maxLive = live;
          steps++;
        }
    }
  double t2 = Now();
  printf("%s, 10000 items, 900x800: first update %.1f ms; %d steps, %.2f ms/step avg, %.2f ms worst; "
         "at most %lu views alive; peak RSS %ld KiB\n", [layout UTF8String], (t1 - t0) * 1000, steps,
         steps ? (t2 - t1) * 1000 / steps : 0, worst * 1000, (unsigned long)maxLive, PeakRSSKiB());
  [win close];
  return maxLive < 200 ? 0 : 1;
}

int main(void)
{
  int fail = 0;
  @autoreleasepool
    {
#ifdef GNUSTEP
      [NSApplication sharedApplication];
#endif
      fail += Run(@"list");
      fail += Run(@"grid");
    }
  printf(fail ? "VBENCH FAIL\n" : "VBENCH OK\n");
  return fail ? 1 : 0;
}
