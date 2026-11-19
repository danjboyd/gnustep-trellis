/* <scroll> with overlay scrollers (headless). Run it twice: with
   -GSTheme Adwaita (overlay scrollers: the content gets the full width and
   the scroller is drawn over it) and with the default theme (legacy
   scrollers: a column of their own).

   Overlay: when the content fits, no scroller is shown and nothing is
   drawn in its strip (it used to draw a track line over the content's
   right edge); when the content overflows, the scroller is shown. Both
   keep the full width for the content.
   Legacy: unchanged, the scroller keeps its column and stays shown.
   Prints SCROLLOVERLAY OK. */
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

static NSString *Spec(int rows)
{
  NSMutableString *s = [NSMutableString stringWithString: @"<column>\n  <scroll id=\"list\"><column>\n"];
  for (int i = 0; i < rows; i++)
    [s appendFormat: @"    <label>Sample item %d</label>\n", i + 1];
  [s appendString: @"  </column></scroll>\n</column>\n<style> #list { height: 160px; } </style>\n"];
  return s;
}

static BOOL ScrollerShown(NSScrollView *s)
{
  NSScroller *v = [s verticalScroller];
  return v != nil && [v superview] != nil && ![v isHidden];
}

/* Any pixel in the scroller's strip that differs from the strip's top-left
   pixel (the background)? */
static BOOL StripIsBlank(TRBoxView *root, NSScrollView *s)
{
  [root display];
  NSRect r = [root bounds];
  NSBitmapImageRep *rep = [root bitmapImageRepForCachingDisplayInRect: r];
  [root cacheDisplayInRect: r toBitmapImageRep: rep];
  NSRect sf = [root convertRect: [s bounds] fromView: s];
  NSInteger scale = (NSInteger)llround([rep pixelsWide] / r.size.width);
  NSInteger x0 = (NSInteger)((NSMaxX(sf) - 14) * scale), x1 = (NSInteger)(NSMaxX(sf) * scale) - 1;
  NSInteger y0 = (NSInteger)((r.size.height - NSMaxY(sf)) * scale), y1 = (NSInteger)((r.size.height - NSMinY(sf)) * scale) - 1;
  if ([root isFlipped]) { y0 = (NSInteger)(NSMinY(sf) * scale); y1 = (NSInteger)(NSMaxY(sf) * scale) - 1; }
  NSColor *bg = [rep colorAtX: x0 y: y0];
  for (NSInteger y = y0; y <= y1; y++)
    for (NSInteger x = x0; x <= x1; x++)
      {
        NSColor *c = [rep colorAtX: x y: y];
        if (fabs([c redComponent] - [bg redComponent]) > 0.02 || fabs([c greenComponent] - [bg greenComponent]) > 0.02
            || fabs([c blueComponent] - [bg blueComponent]) > 0.02)
          return NO;
      }
  return YES;
}

static void RunCase(const char *name, int rows, BOOL overlay)
{
  NSError *err = nil;
  TRMarkupDocument *d = [TRMarkupDocument documentWithString: Spec(rows) name: @"overlay.trellis" error: &err];
  TRBoxView *root = d ? [TRLoader loadDocument: d owner: nil error: &err] : nil;
  if (root == nil) { Expect("spec loads", NO); return; }
  NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 320, 200)
                                            styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: NO];
  [root setFrame: NSMakeRect(0, 0, 320, 200)];
  [[w contentView] addSubview: root];
  [root layoutTrellis];
  NSScrollView *s = (NSScrollView *)[TRLoader viewWithIdentifier: @"list" inView: root];
#ifndef GNUSTEP
  /* AppKit follows the system's scroller setting (System Settings >
     Appearance > Show scroll bars, and the pointing device), not a theme:
     set the style under test on the scroll view and lay out again. */
  [s setScrollerStyle: overlay ? NSScrollerStyleOverlay : NSScrollerStyleLegacy];
  [root layoutTrellis];
#endif
  CGFloat sw = [s frame].size.width, doc = [[s documentView] frame].size.width;
  BOOL fits = [[s documentView] frame].size.height <= [s contentSize].height + 0.5;
  char msg[256];
  if (overlay)
    {
      snprintf(msg, sizeof msg, "%s: content gets the full width (%g of %g)", name, doc, sw);
      Expect(msg, fabs(doc - sw) < 0.5);
      if (fits)
        {
#ifdef GNUSTEP
          /* AppKit keeps an overlay scroller in the view tree and fades it
             out, so "shown" is only checked here; the strip is checked on
             both. */
          snprintf(msg, sizeof msg, "%s: no scroller when the content fits", name);
          Expect(msg, !ScrollerShown(s));
#endif
          snprintf(msg, sizeof msg, "%s: nothing drawn in the scroller strip", name);
          Expect(msg, StripIsBlank(root, s));
        }
#ifdef GNUSTEP
      else
        {
          snprintf(msg, sizeof msg, "%s: scroller shown when the content overflows", name);
          Expect(msg, ScrollerShown(s));
        }
#endif
    }
  else
    {
      snprintf(msg, sizeof msg, "%s: legacy scroller keeps its column (%g of %g)", name, doc, sw);
      Expect(msg, doc < sw - 0.5 && fabs(doc - [s contentSize].width) < 0.5);
      snprintf(msg, sizeof msg, "%s: legacy scroller stays shown", name);
      Expect(msg, ScrollerShown(s));
    }
  [root removeFromSuperview];
}

int main(int argc, char **argv)
{
  @autoreleasepool
    {
      [NSApplication sharedApplication];
#ifdef GNUSTEP
      NSString *theme = [[NSUserDefaults standardUserDefaults] stringForKey: @"GSTheme"];
      BOOL overlay = [theme isEqualToString: @"Adwaita"];
      printf("theme %s (%s scrollers expected)\n", theme ? [theme UTF8String] : "default", overlay ? "overlay" : "legacy");
      RunCase("fits", 2, overlay);
      RunCase("overflows", 30, overlay);
#else
      /* Both styles, set on the scroll view, whatever the system prefers. */
      printf("AppKit (system prefers %s scrollers; both tested)\n",
             [NSScroller preferredScrollerStyle] == NSScrollerStyleOverlay ? "overlay" : "legacy");
      RunCase("legacy fits", 2, NO);
      RunCase("legacy overflows", 30, NO);
      RunCase("overlay fits", 2, YES);
      RunCase("overlay overflows", 30, YES);
#endif
      printf("%s\n", gFail ? "SCROLLOVERLAY FAIL" : "SCROLLOVERLAY OK");
    }
  (void)argc; (void)argv;
  return gFail ? 1 : 0;
}
