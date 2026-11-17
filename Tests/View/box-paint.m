/* Box painting (headless): dashed and dotted borders leave gaps along
   an edge, solid and double ones don't; `border: 2px none` has no width.
   Prints BOXPAINT OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  fflush(stdout);
  if (!ok) gFail++;
}

/* Renders a 120x40 box with the given style on white and counts the
   pixels along row y (from the top) that are mostly red. */
static NSBitmapImageRep *Render(NSString *style)
{
  TRBoxView *outer = [[TRBoxView alloc] initWithStyle: @"background-color: #ffffff; padding: 0"];
  TRBoxView *b = [[TRBoxView alloc] initWithStyle: style];
  [outer addSubview: b style: @"width: 120px; height: 40px"];
  /* GNUstep draws only views in a window. */
  NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 120, 40)
                                              styleMask: NSWindowStyleMaskBorderless
                                                backing: NSBackingStoreBuffered defer: NO];
  [win setReleasedWhenClosed: NO];
  [win setContentView: outer];
  [outer setFrame: NSMakeRect(0, 0, 120, 40)];
  [outer layoutTrellis];
  [outer display];
  NSBitmapImageRep *rep = [outer bitmapImageRepForCachingDisplayInRect: [outer bounds]];
  [outer cacheDisplayInRect: [outer bounds] toBitmapImageRep: rep];
  return rep;
}

static BOOL IsRed(NSBitmapImageRep *rep, NSInteger x, NSInteger y)
{
  NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  return [c redComponent] > 0.7 && [c greenComponent] < 0.4 && [c blueComponent] < 0.4;
}

static NSInteger RedRun(NSBitmapImageRep *rep, NSInteger y, NSInteger *transitions)
{
  NSInteger n = 0, t = 0;
  BOOL prev = NO;
  /* Skip the corners. */
  for (NSInteger x = 12; x < [rep pixelsWide] - 12; x++)
    {
      BOOL red = IsRed(rep, x, y);
      if (red) n++;
      if (x > 12 && red != prev) t++;
      prev = red;
    }
  if (transitions) *transitions = t;
  return n;
}

int main(void)
{
  @autoreleasepool
    {
#ifdef GNUSTEP
      [NSApplication sharedApplication];
#endif
      NSInteger span = 120 - 24, t = 0, n;
      CGFloat scale = 1;

      NSBitmapImageRep *solid = Render(@"border: 4px solid #ff0000");
      scale = [solid pixelsWide] / 120.0;
      n = RedRun(solid, (NSInteger)(2 * scale), &t);
      Expect("solid: the top edge is unbroken", n >= (NSInteger)(span * scale) - 1 && t == 0);

      NSBitmapImageRep *dashed = Render(@"border: 4px dashed #ff0000");
      n = RedRun(dashed, (NSInteger)(2 * scale), &t);
      printf("     dashed: %ld red of %ld, %ld transitions\n", (long)n, (long)(span * scale), (long)t);
      Expect("dashed: the top edge has gaps", n > span * scale * 0.4 && n < span * scale * 0.8 && t >= 6);

      NSBitmapImageRep *dotted = Render(@"border: 4px dotted #ff0000");
      n = RedRun(dotted, (NSInteger)(2 * scale), &t);
      printf("     dotted: %ld red of %ld, %ld transitions\n", (long)n, (long)(span * scale), (long)t);
      Expect("dotted: the top edge is dots", n > span * scale * 0.2 && n < span * scale * 0.7 && t >= 16);

      NSBitmapImageRep *dbl = Render(@"border: 6px double #ff0000");
      Expect("double: outer line drawn", RedRun(dbl, (NSInteger)(1 * scale), NULL) >= (NSInteger)(span * scale) - 1);
      Expect("double: gap between the lines", RedRun(dbl, (NSInteger)(3 * scale), NULL) == 0);
      Expect("double: inner line drawn", RedRun(dbl, (NSInteger)(5 * scale), NULL) >= (NSInteger)(span * scale) - 1);

      /* The standalone property works too. */
      NSBitmapImageRep *longhand = Render(@"border-width: 4px; border-style: dashed; border-color: #ff0000");
      RedRun(longhand, (NSInteger)(2 * scale), &t);
      printf("     longhand: %ld transitions\n", (long)t);
      Expect("border-style: dashed (longhand) has gaps", t >= 6);

      TRBoxView *none = [[TRBoxView alloc] initWithStyle: @"border: 2px none #ff0000"];
      [none setFrame: NSMakeRect(0, 0, 50, 50)];
      [none layoutTrellis];
      Expect("border: 2px none has no width", [none.node layoutBorderForEdge: TREdgeTop] == 0);
    }
  printf(gFail ? "BOXPAINT FAIL (%d)\n" : "BOXPAINT OK\n", gFail);
  return gFail ? 1 : 0;
}
