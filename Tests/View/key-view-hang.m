/* Regression check: the managed key-view loop must never make GNUstep's
   -nextValidKeyView / -previousValidKeyView spin. They walk the chain
   until they find a view that can become key, nil, or their start, so a
   closed ring whose members are all hidden or disabled used to hang
   (0.2.0-0.2.1). An alarm turns a hang into a failure. Prints
   KEYHANG OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"
#include <signal.h>
#include <unistd.h>

static NSString *const kSpec =
  @"<column id=\"root\">\n"
  @"  <field id=\"a\"/>\n"
  @"  <row><button id=\"b\" action=\"go:\">B</button><checkbox id=\"c\">C</checkbox></row>\n"
  @"  <scroll><column><field id=\"d\"/></column></scroll>\n"
  @"</column>\n";

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  fflush(stdout);
  if (!ok) gFail++;
}

static void OnAlarm(int sig)
{
  (void)sig;
  static const char m[] = "FAIL a key-view search hung (alarm)\nKEYHANG FAIL\n";
  write(1, m, sizeof m - 1);
  _exit(1);
}

int main(void)
{
  @autoreleasepool
    {
#ifdef GNUSTEP
      [NSApplication sharedApplication];
#endif
      signal(SIGALRM, OnAlarm);
      alarm(20);
      NSError *err = nil;
      TRMarkupDocument *doc = [TRMarkupDocument documentWithString: kSpec name: @"keyhang.trellis" error: &err];
      TRBoxView *box = doc ? [TRLoader loadDocument: doc owner: nil error: &err] : nil;
      if (box == nil) { printf("load failed: %s\n", [[err localizedDescription] UTF8String]); return 2; }
      NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 400, 300)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered defer: YES];
      [win setReleasedWhenClosed: NO];
      NSView *content = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)];
      [win setContentView: content];
      /* A view outside the Trellis tree whose chain leads into the loop,
         as an app's own controls do. */
      NSTextField *outside = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 280, 100, 20)];
      [content addSubview: outside];
      [box setFrame: NSMakeRect(0, 0, 400, 270)];
      [content addSubview: box];
      [box layoutTrellis];
      NSArray *ids = @[@"a", @"b", @"c", @"d"];
      NSMutableArray *views = [NSMutableArray array];
      for (NSString *i in ids) [views addObject: [TRLoader viewWithIdentifier: i inView: box]];
      NSTextField *a = views[0], *d = views[3];
      Expect("a valid loop still wraps (d -> a)", [d nextValidKeyView] == a);
      Expect("and backwards (a -> d)", [a previousValidKeyView] == d);
      [outside setNextKeyView: box.firstKeyView];

      /* 1. Every control hidden by the app after the loop was built. */
      for (NSView *v in views) [v setHidden: YES];
      Expect("all hidden: next from inside returns", [a nextValidKeyView] == nil || [a nextValidKeyView] == a);
      Expect("all hidden: next from outside returns nil", [outside nextValidKeyView] == nil);
      Expect("all hidden: previous returns (nil or outside)", [d previousValidKeyView] == nil || [d previousValidKeyView] == outside);
      for (NSView *v in views) [v setHidden: NO];

      /* 2. Every control disabled. */
      for (NSControl *v in views) [v setEnabled: NO];
      Expect("all disabled: next from outside returns nil", [outside nextValidKeyView] == nil);
      Expect("all disabled: previous from inside returns (nil or outside)", [d previousValidKeyView] == nil || [d previousValidKeyView] == outside);
      for (NSControl *v in views) [v setEnabled: YES];

      /* 3. The whole box hidden (an ancestor hidden). */
      [box setHidden: YES];
      Expect("box hidden: next from outside returns nil", [outside nextValidKeyView] == nil);
      [box setHidden: NO];

      /* 4. Relaid out with every control display:none. */
      for (NSView *v in [box subviews]) [box setStyleDeclarations: @"display: none" forSubview: v];
      [box layoutTrellis];
      Expect("display:none everywhere: next from outside returns", [outside nextValidKeyView] == nil
             || [outside nextValidKeyView] == outside);
      Expect("Tab from outside returns", ([win selectKeyViewFollowingView: outside], YES));

      alarm(0);
      printf(gFail ? "KEYHANG FAIL\n" : "KEYHANG OK\n");
      return gFail ? 1 : 0;
    }
}
