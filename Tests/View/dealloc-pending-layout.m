/* Regression check (aimanager's crash on v0.1.1): a box tree freed while
   a deferred layout is pending must not be messaged afterwards. Also
   checks that a pending layout still runs for a live box. Run it with
   NSZombieEnabled=YES to turn a stray message into a hard failure.
   Prints DEALLOC OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"

static NSString *const kSpec =
  @"<column id=\"root\">\n"
  @"  <row id=\"inner\"><label id=\"a\">A</label><button id=\"b\" title=\"B\"/></row>\n"
  @"  <scroll><column><label id=\"c\">C</label></column></scroll>\n"
  @"</column>\n";

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok) gFail++;
}

static void Spin(double seconds)
{
  NSDate *until = [NSDate dateWithTimeIntervalSinceNow: seconds];
  while ([until timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                             beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
}

int main(void)
{
  @autoreleasepool
    {
#ifdef GNUSTEP
      [NSApplication sharedApplication];
#endif
      __weak TRBoxView *weakRoot = nil;
      __weak TRBoxView *weakInner = nil;
      for (int round = 0; round < 20; round++)
        {
          @autoreleasepool
            {
              NSError *err = nil;
              TRMarkupDocument *doc = [TRMarkupDocument documentWithString: kSpec name: @"dealloc.trellis" error: &err];
              TRBoxView *box = doc ? [TRLoader loadDocument: doc owner: nil error: &err] : nil;
              if (box == nil) { printf("load failed: %s\n", [[err localizedDescription] UTF8String]); return 2; }
              NSView *host = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)];
              [box setFrame: NSMakeRect(0, 0, 300, 200)];
              [host addSubview: box];
              [box layoutTrellis];
              TRBoxView *inner = (TRBoxView *)[TRLoader viewWithIdentifier: @"inner" inView: box];
              /* Removing a control schedules a layout on the root. */
              [[TRLoader viewWithIdentifier: @"b" inView: box] removeFromSuperview];
              [inner setStyleDeclarations: @"gap: 3px"];
              weakRoot = box;
              weakInner = inner;
              [box removeFromSuperview];
              host = nil;
              box = nil;
              inner = nil;
              doc = nil;
            }
          Spin(0.05);
        }
      Expect("the box tree was freed", weakRoot == nil && weakInner == nil);
      Spin(0.5);
      Expect("no layout reached a freed box (no crash)", YES);

      /* A live box still gets its deferred layout. */
      TRBoxView *live = [TRBoxView boxWithStyle: @"flex-direction: row"];
      [live setFrame: NSMakeRect(0, 0, 200, 50)];
      NSView *v = [[NSView alloc] initWithFrame: NSZeroRect];
      [live addSubview: v style: @"width: 40px; height: 10px"];
      Spin(0.2);
      Expect("a live box lays out on its own", fabs([v frame].size.width - 40) < 0.5);

      printf(gFail ? "DEALLOC FAIL\n" : "DEALLOC OK\n");
      return gFail ? 1 : 0;
    }
}
