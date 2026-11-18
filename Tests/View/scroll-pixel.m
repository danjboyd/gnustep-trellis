/* Fractional scroll origins (headless repro). A scroll view whose
   content lands at a fractional position in window space draws its
   1px pinstripes blurred (grey rows) and shifted. Cases:
     A  root box at a whole-point origin, clip scrolled to a whole point
     B  root box placed by the host at a fractional origin (y + 0.5)
     C  root at a whole point, clip scrolled to y = 3.5
   Prints each case's document origin in window space and the share of
   grey pixels in the stripe area, then SCROLLPIXEL OK if A is crisp
   (the baseline). B and C are reported, not asserted: they are the
   repro. Run with -GSScaleFactor 2 for 2x. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"

@interface StripeView : NSView
@end
@implementation StripeView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r
{
  [[NSColor whiteColor] set];
  NSRectFill([self bounds]);
  [[NSColor blackColor] set];
  for (CGFloat y = 0; y < NSHeight([self bounds]); y += 2)
    NSRectFill(NSMakeRect(0, y, NSWidth([self bounds]), 1));
}
@end

static int gFail = 0;

/* Grey share: pixels that are neither near-black nor near-white. */
static double GreyShare(NSBitmapImageRep *rep, NSRect px)
{
  long grey = 0, n = 0;
  for (NSInteger y = NSMinY(px); y < NSMaxY(px); y++)
    for (NSInteger x = NSMinX(px); x < NSMaxX(px); x++)
      {
        NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
        CGFloat v = [c greenComponent];
        if (v > 0.15 && v < 0.85) grey++;
        n++;
      }
  return n ? (double)grey / n : 0;
}

static void RunCase(const char *name, NSPoint rootOrigin, CGFloat scrollY, BOOL baseline)
{
  NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 240, 200)
                                              styleMask: NSWindowStyleMaskBorderless
                                                backing: NSBackingStoreBuffered defer: NO];
  [win setReleasedWhenClosed: NO];
  NSView *content = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 240, 200)];
  [win setContentView: content];
  TRBoxView *root = [[TRBoxView alloc] initWithStyle: @"padding: 10px; background-color: #ffffff"];
  NSScrollView *sv = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 200, 120)];
  [sv setHasVerticalScroller: NO];
  [sv setBorderType: NSNoBorder];
  StripeView *doc = [[StripeView alloc] initWithFrame: NSMakeRect(0, 0, 200, 400)];
  [sv setDocumentView: doc];
  [root addSubview: sv style: @"width: 200px; height: 120px"];
  [content addSubview: root];
  [root setFrame: NSMakeRect(rootOrigin.x, rootOrigin.y, 220, 140)];
  [root layoutTrellis];
  [[sv contentView] scrollToPoint: NSMakePoint(0, scrollY)];
  [sv reflectScrolledClipView: [sv contentView]];
  [content display];

  NSPoint o = [doc convertPoint: NSZeroPoint toView: nil];
  NSRect clipWin = [[sv contentView] convertRect: [[sv contentView] bounds] toView: nil];
  NSBitmapImageRep *rep = [content bitmapImageRepForCachingDisplayInRect: [content bounds]];
  [content cacheDisplayInRect: [content bounds] toBitmapImageRep: rep];
  CGFloat scale = [rep pixelsWide] / NSWidth([content bounds]);
  /* The stripe area in bitmap pixels (rows from the top), inset 4pt. */
  NSRect clipC = [[sv contentView] convertRect: [[sv contentView] bounds] toView: content];
  NSRect area = NSInsetRect(clipC, 4, 4);
  NSRect px = NSMakeRect(NSMinX(area) * scale, (NSHeight([content bounds]) - NSMaxY(area)) * scale,
                         NSWidth(area) * scale, NSHeight(area) * scale);
  double g = GreyShare(rep, px);
  printf("%s root=(%g,%g) scrollY=%g scale=%g px=%ldx%ld doc-in-window=(%g,%g) clip-in-window=(%g,%g) grey=%.1f%%\n",
         name, rootOrigin.x, rootOrigin.y, scrollY, scale, (long)[rep pixelsWide], (long)[rep pixelsHigh], o.x, o.y,
         clipWin.origin.x, clipWin.origin.y, g * 100);
  if (baseline && g > 0.02) { printf("FAIL %s: baseline stripes are blurred\n", name); gFail++; }
  [win close];
}

int main(void)
{
  @autoreleasepool
    {
      [NSApplication sharedApplication];
      RunCase("A", NSMakePoint(10, 20), 0, YES);
      RunCase("B", NSMakePoint(10, 20.5), 0, NO);
      RunCase("B2", NSMakePoint(10.25, 20.25), 0, NO);
      RunCase("C", NSMakePoint(10, 20), 3.5, NO);
      RunCase("C2", NSMakePoint(10, 20), 3.25, NO);
      printf(gFail ? "SCROLLPIXEL FAIL\n" : "SCROLLPIXEL OK\n");
    }
  return gFail ? 1 : 0;
}
