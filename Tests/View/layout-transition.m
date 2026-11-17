/* Layout transitions (headless): a style change animates when the box
   asks for it, a resize doesn't, reduce-motion turns it off, a change
   mid-way starts from where the views are, and a box freed mid-animation
   stays clean (run with NSZombieEnabled). Prints TRANSITION OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"

static NSString *const kSpec =
  @"<column id=\"root\" class=\"root\">\n"
  @"  <box id=\"banner\" class=\"banner\"></box>\n"
  @"  <row id=\"rowA\" class=\"item\"><label>A</label></row>\n"
  @"  <row id=\"rowB\" class=\"item\"><label>B</label></row>\n"
  @"  <column id=\"inner\" class=\"inner\"><box id=\"tall\" class=\"tall\"></box><box id=\"dot\" class=\"dot\"></box></column>\n"
  @"</column>\n"
  @"<style>\n"
  @"  .root   { -tr-layout-transition: 200ms; gap: 4px; }\n"
  @"  .banner { height: 60px; }\n"
  @"  .item   { height: 30px; }\n"
  @"  .tall   { height: 40px; }\n"
  @"  .dot    { height: 10px; }\n"
  @"</style>\n";

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  fflush(stdout);
  if (!ok) gFail++;
}

static void RunFor(double seconds)
{
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
  while ([end timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.005]];
}

static NSView *V(TRBoxView *root, NSString *ident) { return [TRLoader viewWithIdentifier: ident inView: root]; }

int main(void)
{
  @autoreleasepool
    {
#ifdef GNUSTEP
      [NSApplication sharedApplication];
#endif
      [TRBoxView setReducesMotionOverride: @NO];
      NSError *err = nil;
      TRMarkupDocument *doc = [TRMarkupDocument documentWithString: kSpec name: @"transition.trellis" error: &err];
      TRBoxView *root = doc ? [TRLoader loadDocument: doc owner: nil error: &err] : nil;
      if (root == nil) { printf("load failed: %s\n", [[err localizedDescription] UTF8String]); return 2; }
      NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 400)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered defer: YES];
      [win setReleasedWhenClosed: NO];
      [win setContentView: root];
      [root layoutTrellis];
      RunFor(0.05);
      NSView *a = V(root, @"rowA"), *banner = V(root, @"banner");
      CGFloat y0 = [a frame].origin.y;
      Expect("first layout places without animating", ![root isAnimatingLayout] && y0 == 64);

      /* Hide the banner: rows move up 64 px over 200 ms. */
      [root setStyleDeclarations: @"display: none" forSubview: banner];
      RunFor(0.06);
      CGFloat mid = [a frame].origin.y;
      printf("     row A: %.1f -> %.1f (mid-way)\n", y0, mid);
      Expect("animating after a style change", [root isAnimatingLayout]);
      Expect("mid-way between the old and new frames", mid < y0 - 1 && mid > 1);
      RunFor(0.3);
      Expect("ends at the new frame", ![root isAnimatingLayout] && [a frame].origin.y == 0);

      /* Nested boxes animate too (the transition inherits). */
      NSView *dot = V(root, @"dot");
      CGFloat d0 = [dot frame].origin.y;
      [(TRBoxView *)V(root, @"inner") setStyleDeclarations: @"height: 10px" forSubview: V(root, @"tall")];
      RunFor(0.06);
      CGFloat dm = [dot frame].origin.y;
      RunFor(0.3);
      printf("     nested dot: %.1f -> %.1f -> %.1f\n", d0, dm, [dot frame].origin.y);
      Expect("a nested box's subviews animate", dm < d0 && dm > [dot frame].origin.y);

      /* Interrupt: show the banner again mid-way, then hide it again. */
      [root setStyleDeclarations: @"display: flex; height: 60px" forSubview: banner];
      RunFor(0.08);
      CGFloat before = [a frame].origin.y;
      [root setStyleDeclarations: @"display: none" forSubview: banner];
      RunFor(0.02);
      CGFloat after = [a frame].origin.y;
      printf("     interrupted at %.1f, then %.1f\n", before, after);
      Expect("a change mid-way starts from where the view is", fabs(after - before) < 30 && after <= before);
      RunFor(0.3);
      Expect("and ends at the newest frame", [a frame].origin.y == 0);

      /* A resize never animates. */
      [win setContentSize: NSMakeSize(260, 380)];
      [root setFrame: NSMakeRect(0, 0, 260, 380)];
      Expect("resize is immediate", ![root isAnimatingLayout] && [a frame].size.width == 260);

      /* Reduce motion: changes jump. */
      [TRBoxView setReducesMotionOverride: @YES];
      [root setStyleDeclarations: @"display: flex; height: 60px" forSubview: banner];
      RunFor(0.03);
      Expect("reduced motion: no animation", ![root isAnimatingLayout] && [a frame].origin.y == 64);
      [TRBoxView setReducesMotionOverride: @NO];

      /* -tr-layout-transition: none on a nested box stops it there. */
      [root setStyleDeclarations: @"-tr-layout-transition: none" forSubview: V(root, @"inner")];
      [root layoutTrellis];
      RunFor(0.3);
      CGFloat dn = [dot frame].origin.y;
      [(TRBoxView *)V(root, @"inner") setStyleDeclarations: @"height: 40px" forSubview: V(root, @"tall")];
      RunFor(0.04);
      Expect("none on a nested box: its subviews jump", [dot frame].origin.y == dn + 30);

      /* Freed mid-animation. */
      @autoreleasepool
        {
          [root setStyleDeclarations: @"display: none" forSubview: banner];
          RunFor(0.04);
          Expect("animating before the free", [root isAnimatingLayout]);
          [win setContentView: [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)]];
          root = nil;
          a = banner = dot = nil;
        }
      RunFor(0.3);
      [win close];
    }
  printf(gFail ? "TRANSITION FAIL\n" : "TRANSITION OK\n");
  return gFail ? 1 : 0;
}
