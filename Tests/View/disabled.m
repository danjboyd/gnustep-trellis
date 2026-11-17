/* disabled (headless): on a control, on a container (every control in
   it, labels left alone), on a split; disabled controls stay in the
   key-view loop and Tab skips them; TRSetEnabled turns them back on with
   no relayout. Prints DISABLED OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"

static NSString *const kSpec =
  @"<column>\n"
  @"  <field id=\"a\" a11y-label=\"A\"/>\n"
  @"  <button id=\"b\" disabled>Send</button>\n"
  @"  <row id=\"grp\" disabled=\"yes\"><label id=\"lab\">Proxy</label><field id=\"c\" a11y-label=\"C\"/>"
  @"<checkbox id=\"d\">D</checkbox></row>\n"
  @"  <split id=\"sp\" disabled class=\"sp\"><column><field id=\"e\" a11y-label=\"E\"/></column><column/></split>\n"
  @"  <field id=\"f\" a11y-label=\"F\" disabled=\"no\"/>\n"
  @"</column>\n"
  @"<style> .sp { height: 60px; flex: none; } </style>\n";

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok) gFail++;
}

static NSView *Focused(NSWindow *win)
{
  id fr = [win firstResponder];
  if ([fr isKindOfClass: [NSText class]] && [(NSText *)fr isFieldEditor]) fr = [(NSText *)fr delegate];
  return [fr isKindOfClass: [NSView class]] ? fr : nil;
}

static void SendTab(NSWindow *win)
{
  NSEvent *e = [NSEvent keyEventWithType: NSEventTypeKeyDown location: NSZeroPoint modifierFlags: 0
                               timestamp: 0 windowNumber: [win windowNumber] context: nil
                              characters: @"\t" charactersIgnoringModifiers: @"\t" isARepeat: NO keyCode: 48];
  [win sendEvent: e];
}

int main(void)
{
  @autoreleasepool
    {
#ifdef GNUSTEP
      [NSApplication sharedApplication];
#endif
      NSError *err = nil;
      TRMarkupDocument *doc = [TRMarkupDocument documentWithString: kSpec name: @"disabled.trellis" error: &err];
      TRBoxView *box = doc ? [TRLoader loadDocument: doc owner: nil error: &err] : nil;
      if (box == nil) { printf("load failed: %s\n", [[err localizedDescription] UTF8String]); return 2; }
      NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 400, 300)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered defer: NO];
      [win setReleasedWhenClosed: NO];
      [box setFrame: NSMakeRect(0, 0, 400, 300)];
      [win setContentView: box];
      [win orderFront: nil];
      [box layoutTrellis];
#define V(i) ((NSControl *)[TRLoader viewWithIdentifier: @i inView: box])
      Expect("disabled button", ![V("b") isEnabled]);
      Expect("disabled row: its field and checkbox", ![V("c") isEnabled] && ![V("d") isEnabled]);
      Expect("disabled row: its label left alone", [V("lab") isEnabled]);
      Expect("disabled split: the pane's field", ![V("e") isEnabled]);
      Expect("disabled=\"no\" and the rest stay enabled", [V("f") isEnabled] && [V("a") isEnabled]);

      [win makeFirstResponder: V("a")];
      SendTab(win);
      printf("     Tab from a: %s\n", [[Focused(win) identifier] ?: @"(none)" UTF8String]);
      Expect("Tab skips the disabled controls", Focused(win) == V("f"));

      /* Enabled again in code, with no relayout: Tab finds them. */
      TRSetEnabled([TRLoader viewWithIdentifier: @"grp" inView: box], YES);
      Expect("TRSetEnabled on the row", [V("c") isEnabled] && [V("d") isEnabled]);
      [win makeFirstResponder: V("a")];
      SendTab(win);
      printf("     Tab from a after enabling: %s\n", [[Focused(win) identifier] ?: @"(none)" UTF8String]);
      Expect("enabled controls are back in the Tab order", Focused(win) == V("c"));
      [win close];

      TRMarkupDocument *bd = [TRMarkupDocument documentWithString: @"<column><button disabled=\"greyed\">X</button></column>"
                                                             name: @"bad.trellis" error: NULL];
      Expect("disabled=\"greyed\" is an error", [TRLoader loadDocument: bd owner: nil error: &err] == nil);
    }
  printf(gFail ? "DISABLED FAIL (%d)\n" : "DISABLED OK\n", gFail);
  return gFail ? 1 : 0;
}
