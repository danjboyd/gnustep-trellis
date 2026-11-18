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

static void Check(const char *name, const char *what, BOOL ok)
{
  if (!ok) { printf("FAIL %s: %s\n", name, what); gFail++; }
}

/* rootOrigin: where the host puts the root box. moveTo (if not NAN): the
   host then moves it there without resizing (only -setFrameOrigin:). */
static void RunCase(const char *name, NSPoint rootOrigin, NSPoint moveTo, CGFloat scrollY)
{
  NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 240, 220)
                                              styleMask: NSWindowStyleMaskBorderless
                                                backing: NSBackingStoreBuffered defer: NO];
  [win setReleasedWhenClosed: NO];
  NSView *content = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 240, 220)];
  [win setContentView: content];
  TRBoxView *root = [[TRBoxView alloc] initWithStyle: @"flex-direction: column; padding: 10px; gap: 0; background-color: #ffffff"];
  TRBoxView *bar = [[TRBoxView alloc] initWithStyle: @"background-color: #ff0000"];
  [root addSubview: bar style: @"width: 200px; height: 10px"];
  NSScrollView *sv = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 200, 120)];
  [sv setHasVerticalScroller: NO];
  [sv setBorderType: NSNoBorder];
  StripeView *doc = [[StripeView alloc] initWithFrame: NSMakeRect(0, 0, 200, 400)];
  [sv setDocumentView: doc];
  [root addSubview: sv style: @"width: 200px; height: 120px"];
  [content addSubview: root];
  [root setFrame: NSMakeRect(rootOrigin.x, rootOrigin.y, 220, 150)];
  [root layoutTrellis];
  if (!isnan(moveTo.x)) [root setFrameOrigin: moveTo];
  [[sv contentView] scrollToPoint: NSMakePoint(0, scrollY)];
  [sv reflectScrolledClipView: [sv contentView]];
  [content display];

  NSPoint o = [doc convertPoint: NSZeroPoint toView: nil];
  NSBitmapImageRep *rep = [content bitmapImageRepForCachingDisplayInRect: [content bounds]];
  [content cacheDisplayInRect: [content bounds] toBitmapImageRep: rep];
  CGFloat scale = [rep pixelsWide] / NSWidth([content bounds]);
  /* The stripe area in bitmap pixels (rows from the top), inset 4pt. */
  NSRect clipC = [[sv contentView] convertRect: [[sv contentView] bounds] toView: content];
  NSRect area = NSInsetRect(clipC, 4, 4);
  NSRect px = NSMakeRect(NSMinX(area) * scale, (NSHeight([content bounds]) - NSMaxY(area)) * scale,
                         NSWidth(area) * scale, NSHeight(area) * scale);
  double g = GreyShare(rep, px);

  /* Layout frames (what the engine placed) against the views' frames. */
  TRNode *svNode = nil, *barNode = nil;
  for (TRNode *c in root.node.children)
    {
      if (c.context == sv) svNode = c;
      if (c.context == bar) barNode = c;
    }
  NSRect svLayout = NSMakeRect(svNode.layoutFrame.x, svNode.layoutFrame.y,
                               svNode.layoutFrame.width, svNode.layoutFrame.height);
  NSRect barLayout = NSMakeRect(barNode.layoutFrame.x, barNode.layoutFrame.y,
                                barNode.layoutFrame.width, barNode.layoutFrame.height);
  NSRect svF = [sv frame];
  CGFloat dx = svF.origin.x - svLayout.origin.x, dy = svF.origin.y - svLayout.origin.y;
  printf("%s root=(%g,%g)%s scrollY=%g scale=%g doc-in-window=(%g,%g) nudge=(%g,%g) grey=%.1f%%\n",
         name, rootOrigin.x, rootOrigin.y, isnan(moveTo.x) ? "" : " then moved", scrollY, scale,
         o.x, o.y, dx, dy, g * 100);
  if (getenv("SCROLLPIXEL_DEBUG"))
    {
      NSView *clip = [sv contentView];
      printf("   sv.frame=%s sv@win=%s clip.frame=%s clip.bounds=%s clip@win=%s doc.frame=%s\n",
             [NSStringFromRect(svF) UTF8String],
             [NSStringFromPoint([[sv superview] convertPoint: svF.origin toView: nil]) UTF8String],
             [NSStringFromRect([clip frame]) UTF8String], [NSStringFromRect([clip bounds]) UTF8String],
             [NSStringFromPoint([clip convertPoint: [clip bounds].origin toView: nil]) UTF8String],
             [NSStringFromRect([doc frame]) UTF8String]);
    }
  Check(name, "stripes are blurred (grey > 2%)", g <= 0.02);
  Check(name, "the scroll view moved a device pixel or more",
        fabs(dx) < 1.0 / scale - 1e-6 && fabs(dy) < 1.0 / scale - 1e-6);
  Check(name, "the scroll view changed size", NSEqualSizes(svF.size, svLayout.size));
  Check(name, "the sibling bar moved off its layout frame", NSEqualRects([bar frame], barLayout));
  Check(name, "the root's own frame changed",
        NSEqualSizes([root frame].size, NSMakeSize(220, 150))
        && NSEqualPoints([root frame].origin, isnan(moveTo.x) ? rootOrigin : moveTo));
  /* Clipping: the clip view fills the scroll view and shows the top of
     the document (or the scrolled offset). */
  Check(name, "the clip view doesn't fill the scroll view",
        NSEqualRects([[sv contentView] frame], [sv bounds]));
  Check(name, "the clip's visible height changed",
        fabs(NSHeight([[sv contentView] documentVisibleRect]) - 120) < 1e-6);
  /* Hit targets: the middle of the scroll area hits the document, the
     middle of the bar hits the bar, and 1pt above the scroll view's top
     edge is the bar, not the scroll view. */
  NSPoint mid = NSMakePoint(NSMidX(clipC), NSMidY(clipC));
  NSView *hit = [content hitTest: mid];
  Check(name, "the scroll area's middle doesn't hit the document", hit == doc || [hit isDescendantOf: sv]);
  NSRect barC = [root convertRect: [bar frame] toView: content];
  hit = [content hitTest: NSMakePoint(NSMidX(barC), NSMidY(barC))];
  Check(name, "the bar's middle doesn't hit the bar", hit == bar);
  NSRect svC = [root convertRect: svF toView: content];
  hit = [content hitTest: NSMakePoint(NSMidX(svC), NSMaxY(svC) + 1)];
  Check(name, "1pt above the scroll view isn't the bar", hit == bar);
  [win close];
}

int main(void)
{
  @autoreleasepool
    {
      [NSApplication sharedApplication];
      NSPoint stay = NSMakePoint(NAN, NAN);
      RunCase("A", NSMakePoint(10, 20), stay, 0);
      RunCase("B", NSMakePoint(10, 20.5), stay, 0);
      RunCase("B2", NSMakePoint(10.25, 20.25), stay, 0);
      RunCase("B3", NSMakePoint(10.75, 20.6), stay, 0);
      RunCase("C", NSMakePoint(10, 20), stay, 3.5);
      RunCase("C2", NSMakePoint(10.25, 20.25), stay, 3.25);
      RunCase("D", NSMakePoint(10, 20), NSMakePoint(10.25, 20.5), 0);
      printf(gFail ? "SCROLLPIXEL FAIL\n" : "SCROLLPIXEL OK\n");
    }
  return gFail ? 1 : 0;
}
