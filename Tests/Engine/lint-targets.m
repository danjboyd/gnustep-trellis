/* The touch-target lint (WCAG 2.2, 2.5.8): small controls are flagged
   only when their 24 px circle reaches another target; hidden controls,
   non-interactive views and targets in another scroller don't count.
   Prints LINTTARGETS OK. */
#import <Foundation/Foundation.h>
#import "TRLint.h"

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok) gFail++;
}

static NSDictionary *Box(double x, double y, double w, double h, NSArray *kids, NSDictionary *extra)
{
  NSMutableDictionary *d = [@{@"class": @"TRBoxView", @"x": @(x), @"y": @(y), @"width": @(w), @"height": @(h)} mutableCopy];
  if (kids) d[@"children"] = kids;
  [d addEntriesFromDictionary: extra ?: @{}];
  return d;
}

static NSDictionary *Btn(NSString *ident, double x, double y, double w, double h)
{
  return @{@"class": @"NSButton", @"id": ident, @"interactive": @YES,
           @"x": @(x), @"y": @(y), @"width": @(w), @"height": @(h)};
}

static NSUInteger Targets(NSArray *kids)
{
  NSUInteger n = 0;
  for (NSDictionary *f in TRLintFrameTree(Box(0, 0, 400, 300, kids, nil), 400, 300))
    if ([f[@"rule"] isEqualToString: @"touch-target"]) n++;
  return n;
}

int main(void)
{
  @autoreleasepool
    {
      Expect("24x24 targets touching each other pass", Targets(@[Btn(@"a", 0, 0, 24, 24), Btn(@"b", 24, 0, 24, 24)]) == 0);
      Expect("16x16 icons 2 px apart are flagged (both)",
             Targets(@[Btn(@"a", 0, 0, 16, 16), Btn(@"b", 18, 0, 16, 16)]) == 2);
      Expect("16x16 icons 30 px apart pass (spacing exception)",
             Targets(@[Btn(@"a", 0, 0, 16, 16), Btn(@"b", 30, 0, 16, 16)]) == 0);
      Expect("22 px tall push buttons in a row with a gap pass",
             Targets(@[Btn(@"a", 0, 0, 90, 22), Btn(@"b", 96, 0, 90, 22)]) == 0);
      Expect("22 px tall rows stacked 1 px apart are flagged",
             Targets(@[Btn(@"a", 0, 0, 120, 22), Btn(@"b", 0, 23, 120, 22)]) == 2);
      Expect("a small target near a big one: flagged within 12 px, not at 12",
             Targets(@[Btn(@"a", 0, 0, 16, 16), Btn(@"big", 18, 0, 80, 30)]) == 1 && Targets(@[Btn(@"a", 0, 0, 16, 16), Btn(@"big", 20, 0, 80, 30)]) == 0);
      NSMutableDictionary *hidden = [Btn(@"b", 18, 0, 16, 16) mutableCopy];
      hidden[@"hidden"] = @YES;
      Expect("hidden controls don't count", Targets(@[Btn(@"a", 0, 0, 16, 16), hidden]) == 0);
      NSDictionary *label = @{@"class": @"NSTextField", @"x": @18, @"y": @0, @"width": @40, @"height": @16};
      Expect("non-interactive views don't count", Targets(@[Btn(@"a", 0, 0, 16, 16), label]) == 0);
      NSDictionary *scroller = Box(0, 20, 200, 100, @[Box(0, 0, 200, 400, @[Btn(@"in", 0, -18, 16, 16)], nil)],
                                   @{@"overflow": @"scroll"});
      Expect("targets in another scroller don't count",
             Targets(@[Btn(@"out", 0, 0, 16, 16), scroller]) == 0);
      NSArray *f = TRLintFrameTree(Box(0, 0, 400, 300, @[Btn(@"close", 0, 0, 16, 16), Btn(@"pin", 18, 0, 16, 16)], nil), 400, 300);
      NSString *msg = [f count] ? f[0][@"message"] : @"";
      Expect("the message names the target, its size and the neighbour",
             [msg rangeOfString: @"#close"].location != NSNotFound && [msg rangeOfString: @"16x16"].location != NSNotFound
             && [msg rangeOfString: @"#pin"].location != NSNotFound && [f[0][@"severity"] isEqualToString: @"warning"]);
      if ([msg length]) printf("     %s\n", [msg UTF8String]);
    }
  printf(gFail ? "LINTTARGETS FAIL\n" : "LINTTARGETS OK\n");
  return gFail ? 1 : 0;
}
