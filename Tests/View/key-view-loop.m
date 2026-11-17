/* Headless check of the keyboard focus order: tabindex first, then
   document order, skipping tabindex="-1" and views hidden by a container
   query; scrolled content joins the loop. Views hidden with the hidden
   attribute or -setHidden:forSubview: leave the loop and come back when
   shown, and hiding the focused view moves focus on. Prints KEYVIEW OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"

static NSString *const kSpec =
  @"<column id=\"root\" class=\"page\">\n"
  @"  <field id=\"a\"/>\n"
  @"  <row><button id=\"b\" action=\"go:\">B</button><checkbox id=\"c\">C</checkbox></row>\n"
  @"  <field id=\"d\" tabindex=\"1\"/>\n"
  @"  <field id=\"e\" tabindex=\"-1\"/>\n"
  @"  <scroll class=\"sc\"><column id=\"sccol\"><field id=\"f\"/></column></scroll>\n"
  @"  <field id=\"g\" class=\"narrow\"/>\n"
  @"  <row id=\"grp\" hidden><field id=\"h\"/></row>\n"
  @"</column>\n"
  @"<style>\n"
  @"  .page { container-type: inline-size; gap: 4px; }\n"
  @"  .sc { flex: none; height: 40px; }\n"
  @"  @container (min-width: 400px) { .narrow { display: none; } }\n"
  @"</style>\n";

static NSString *Loop(TRBoxView *box)
{
  NSMutableArray *ids = [NSMutableArray array];
  NSView *first = box.firstKeyView, *v = first;
  for (int i = 0; v != nil && i < 32; i++)
    {
      /* On GNUstep the chain wraps through a sentinel outside the tree. */
      if (![v isDescendantOf: box]) { v = [v nextKeyView]; if (v == first) break; continue; }
      [ids addObject: [v identifier] ?: @"?"];
      v = [v nextKeyView];
      if (v == first) break;
    }
  return [ids componentsJoinedByString: @","];
}

int main(void)
{
  @autoreleasepool
    {
#ifdef GNUSTEP
      [NSApplication sharedApplication];
#endif
      NSError *err = nil;
      TRMarkupDocument *doc = [TRMarkupDocument documentWithString: kSpec name: @"keyview.trellis" error: &err];
      TRBoxView *box = doc ? [TRLoader loadDocument: doc owner: nil error: &err] : nil;
      if (box == nil) { printf("load failed: %s\n", [[err localizedDescription] UTF8String]); return 2; }
      int ok = 1;
      struct { CGFloat w; const char *want; } cases[] = { { 500, "d,a,b,c,f" }, { 300, "d,a,b,c,f,g" } };
      for (int i = 0; i < 2; i++)
        {
          [box setFrame: NSMakeRect(0, 0, cases[i].w, 400)];
          [box layoutTrellis];
          NSString *got = Loop(box);
          printf("width %g: %s (want %s)\n", cases[i].w, [got UTF8String], cases[i].want);
          if (![got isEqualToString: [NSString stringWithUTF8String: cases[i].want]]) ok = 0;
        }

      /* hidden / -setHidden:forSubview:, in a window so focus can move. */
      NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 400)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered defer: NO];
      [win setReleasedWhenClosed: NO];
      [box setFrame: NSMakeRect(0, 0, 300, 400)];
      [win setContentView: box];
      [box layoutTrellis];
      NSView *grp = [TRLoader viewWithIdentifier: @"grp" inView: box];
      NSView *h = [TRLoader viewWithIdentifier: @"h" inView: box];
      NSView *g = [TRLoader viewWithIdentifier: @"g" inView: box];
      NSView *f = [TRLoader viewWithIdentifier: @"f" inView: box];
      NSView *c = [TRLoader viewWithIdentifier: @"c" inView: box];
      TRBoxView *sccol = (TRBoxView *)[TRLoader viewWithIdentifier: @"sccol" inView: box];
      TRBoxView *page = (TRBoxView *)[grp superview];
#define CHECK(label, cond) do { BOOL _c = (cond); printf("%s: %s\n", _c ? "ok" : "FAIL", label); if (!_c) ok = 0; } while (0)
      CHECK("hidden attribute keeps h out", [Loop(box) isEqualToString: @"d,a,b,c,f,g"]);
      [page setHidden: NO forSubview: grp];
      [box layoutTrellis];
      CHECK("shown again: h joins at its place", [Loop(box) isEqualToString: @"d,a,b,c,f,g,h"]);

      /* Hiding the focused view moves focus to the next one. */
      [win makeFirstResponder: g];
      NSView *fr = (NSView *)[win firstResponder];
      if ([fr isKindOfClass: [NSText class]]) fr = (NSView *)[(NSText *)fr delegate];
      CHECK("g has focus", fr == g);
      [page setHidden: YES forSubview: g];
      [box layoutTrellis];
      fr = (NSView *)[win firstResponder];
      if ([fr isKindOfClass: [NSText class]]) fr = (NSView *)[(NSText *)fr delegate];
      printf("after hiding g, focus is %s\n", [[fr identifier] ?: NSStringFromClass([fr class]) UTF8String]);
      CHECK("focus moved to h", fr == h);
      CHECK("g left the loop", [Loop(box) isEqualToString: @"d,a,b,c,f,h"]);

      /* Hiding a whole box with the focus inside it. */
      [page setHidden: YES forSubview: grp];
      [box layoutTrellis];
      fr = (NSView *)[win firstResponder];
      if ([fr isKindOfClass: [NSText class]]) fr = (NSView *)[(NSText *)fr delegate];
      printf("after hiding grp, focus is %s\n", [[fr identifier] ?: NSStringFromClass([fr class]) UTF8String]);
      CHECK("focus wrapped to d", [fr identifier] && [[fr identifier] isEqualToString: @"d"]);

      /* Scrolled content hiding its own child updates the outer loop. */
      [sccol setHidden: YES forSubview: f];
      [sccol layoutTrellis];
      CHECK("scrolled f left the loop", [Loop(box) isEqualToString: @"d,a,b,c"]);
      [sccol setHidden: NO forSubview: f];
      [sccol layoutTrellis];
      CHECK("scrolled f is back", [Loop(box) isEqualToString: @"d,a,b,c,f"]);
      (void)c;
      [win close];

      printf(ok ? "KEYVIEW OK\n" : "KEYVIEW FAIL\n");
      return ok ? 0 : 1;
    }
}
