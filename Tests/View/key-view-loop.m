/* Headless check of the keyboard focus order: tabindex first, then
   document order, skipping tabindex="-1" and views hidden by a container
   query; scrolled content joins the loop. Prints KEYVIEW OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"

static NSString *const kSpec =
  @"<column id=\"root\" class=\"page\">\n"
  @"  <field id=\"a\"/>\n"
  @"  <row><button id=\"b\" action=\"go:\">B</button><checkbox id=\"c\">C</checkbox></row>\n"
  @"  <field id=\"d\" tabindex=\"1\"/>\n"
  @"  <field id=\"e\" tabindex=\"-1\"/>\n"
  @"  <scroll class=\"sc\"><column><field id=\"f\"/></column></scroll>\n"
  @"  <field id=\"g\" class=\"narrow\"/>\n"
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
      /* The chain wraps through the outermost box (last -> box -> first). */
      if (v == box) { v = [v nextKeyView]; if (v == first) break; continue; }
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
      printf(ok ? "KEYVIEW OK\n" : "KEYVIEW FAIL\n");
      return ok ? 0 : 1;
    }
}
