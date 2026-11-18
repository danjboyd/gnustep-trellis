/* View lookup by id through scroll views (headless): a custom NSScrollView
   with no documentView must not throw, an id inside a populated <scroll>
   is found, ids after an empty scroll view are found, and a missing id is
   nil. Also through +applySample:toView:error:, which looks ids up the
   same way. Prints FINDVIEW OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"

/* A scroll view subclass that never gets a document view. */
@interface EmptyScroll : NSScrollView
@end
@implementation EmptyScroll
@end

static NSString *const kSpec =
  @"<column>\n"
  @"  <label id=\"before\">Before</label>\n"
  @"  <view type=\"EmptyScroll\" id=\"empty\" a11y-label=\"Empty sample\"/>\n"
  @"  <scroll id=\"list\"><column><label id=\"inside\">Inside</label></column></scroll>\n"
  @"  <label id=\"after\">After</label>\n"
  @"</column>\n"
  @"<style> #empty { height: 40px; } #list { height: 60px; } </style>\n";

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  fflush(stdout);
  if (!ok) gFail++;
}

int main(void)
{
  @autoreleasepool
    {
#ifdef GNUSTEP
      [NSApplication sharedApplication];
#endif
      NSError *err = nil;
      TRMarkupDocument *doc = [TRMarkupDocument documentWithString: kSpec name: @"find.trellis" error: &err];
      TRBoxView *root = doc ? [TRLoader loadDocument: doc owner: nil error: &err] : nil;
      Expect("spec loads", root != nil);
      if (root == nil) { printf("  %s\n", [[err localizedDescription] UTF8String]); return 1; }
      NSView *empty = nil;
      @try
        {
          empty = [TRLoader viewWithIdentifier: @"empty" inView: root];
          Expect("the empty scroll view itself is found", [empty isKindOfClass: [EmptyScroll class]]);
          Expect("it really has no document view", [(NSScrollView *)empty documentView] == nil);
          Expect("an id before it is found", [[TRLoader viewWithIdentifier: @"before" inView: root] isKindOfClass: [NSTextField class]]);
          Expect("an id inside a populated scroll is found", [[TRLoader viewWithIdentifier: @"inside" inView: root] isKindOfClass: [NSTextField class]]);
          Expect("an id after the empty scroll view is found", [[TRLoader viewWithIdentifier: @"after" inView: root] isKindOfClass: [NSTextField class]]);
          Expect("a missing id is nil, not an exception", [TRLoader viewWithIdentifier: @"nope" inView: root] == nil);
          Expect("lookup starting at the empty scroll view", [TRLoader viewWithIdentifier: @"nope" inView: empty] == nil);
          NSError *serr = nil;
          BOOL ok = [TRLoader applySample: @{ @"after": @"Changed", @"inside": @"Inside too" } toView: root error: &serr];
          Expect("applySample walks past the empty scroll view", ok
                 && [[(NSTextField *)[TRLoader viewWithIdentifier: @"after" inView: root] stringValue] isEqualToString: @"Changed"]
                 && [[(NSTextField *)[TRLoader viewWithIdentifier: @"inside" inView: root] stringValue] isEqualToString: @"Inside too"]);
        }
      @catch (NSException *e)
        {
          Expect([[NSString stringWithFormat: @"no exception (got %@: %@)", [e name], [e reason]] UTF8String], NO);
        }
      printf("%s\n", gFail ? "FINDVIEW FAIL" : "FINDVIEW OK");
    }
  return gFail ? 1 : 0;
}
