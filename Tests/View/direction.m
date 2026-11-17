/* dir and direction in the view layer (headless): dir="rtl" mirrors a
   row; a box in a split pane or a scroll view, which lays out on its own,
   keeps the outer direction; dir="ltr" inside switches back; logical
   margins follow; a bad dir is a load error. Prints DIRECTION OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"

static NSString *const kSpec =
  @"<column dir=\"rtl\">\n"
  @"  <row id=\"r\"><button id=\"a\">Alpha</button><button id=\"b\">Beta</button></row>\n"
  @"  <row id=\"m\"><label id=\"ml\" style=\"margin-inline-start: 30px\">Start</label></row>\n"
  @"  <split id=\"sp\" class=\"sp\">\n"
  @"    <column id=\"p1\" style=\"width: 150px\"><row id=\"pr\"><label id=\"pl\">Pane</label></row></column>\n"
  @"    <column id=\"p2\" dir=\"ltr\"><row id=\"qr\"><label id=\"ql\">Other</label></row></column>\n"
  @"  </split>\n"
  @"  <scroll id=\"sc\" class=\"sc\"><row id=\"sr\"><label id=\"sl\">Scrolled</label></row></scroll>\n"
  @"</column>\n"
  @"<style> .sp { height: 60px; flex: none; } .sc { height: 60px; flex: none; } </style>\n";

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok) gFail++;
}

/* The view's frame in the coordinates of its enclosing view v. */
static NSRect In(NSView *x, NSView *v) { return [v convertRect: [x bounds] fromView: x]; }

int main(void)
{
  @autoreleasepool
    {
#ifdef GNUSTEP
      [NSApplication sharedApplication];
#endif
      NSError *err = nil;
      TRMarkupDocument *doc = [TRMarkupDocument documentWithString: kSpec name: @"direction.trellis" error: &err];
      TRBoxView *box = doc ? [TRLoader loadDocument: doc owner: nil error: &err] : nil;
      if (box == nil) { printf("load failed: %s\n", [[err localizedDescription] UTF8String]); return 2; }
      NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 400, 300)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered defer: NO];
      [win setReleasedWhenClosed: NO];
      [box setFrame: NSMakeRect(0, 0, 400, 300)];
      [win setContentView: box];
      [box layoutTrellis];
#define V(i) [TRLoader viewWithIdentifier: @i inView: box]
      NSView *a = V("a"), *b = V("b"), *r = V("r");
      Expect("dir=rtl: the first button is right of the second", NSMinX([a frame]) > NSMaxX([b frame]) - 1);
      Expect("dir=rtl: the row starts at the right edge", NSMaxX([a frame]) > NSWidth([r bounds]) - 2);
      NSView *ml = V("ml"), *m = V("m");
      Expect("margin-inline-start is the right margin",
             fabs(NSWidth([m bounds]) - NSMaxX([ml frame]) - 30) < 1);

      /* Split panes lay out on their own, so these need the inheritance. */
      NSView *pl = V("pl"), *pr = V("pr");
      [[pr window] displayIfNeeded];
      NSRect plr = In(pl, pr);
      Expect("a split pane keeps rtl: its label is at the right",
             NSMaxX(plr) > NSWidth([pr bounds]) - 2 && NSMinX(plr) > 2);
      NSView *ql = V("ql"), *qr = V("qr");
      Expect("dir=ltr on a pane switches back: its label is at the left", NSMinX(In(ql, qr)) < 1);
      NSView *sl = V("sl"), *sr = V("sr");
      NSRect slr = In(sl, sr);
      Expect("a scroll view's content keeps rtl", NSMaxX(slr) > NSWidth([sr bounds]) - 2 && NSMinX(slr) > 2);
      Expect("TRBoxView inheritedLayoutDirection inside the pane is rtl",
             [(TRBoxView *)V("p1") inheritedLayoutDirection] == TRDirectionRTL);

      /* A bad value is an error at the element. */
      err = nil;
      TRMarkupDocument *bad = [TRMarkupDocument documentWithString: @"<column dir=\"backwards\"/>"
                                                              name: @"bad.trellis" error: &err];
      Expect("dir=\"backwards\" is an error", bad == nil
             && [[err localizedDescription] rangeOfString: @"use ltr or rtl"].location != NSNotFound);
      printf("%s\n", gFail ? "DIRECTION FAIL" : "DIRECTION OK");
    }
  return gFail ? 1 : 0;
}
