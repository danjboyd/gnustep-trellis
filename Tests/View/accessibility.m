/* Headless check of the accessibility attributes: a11y-label, label-for
   and role are recorded on every platform and, on Cocoa, reach
   NSAccessibility. A label-for without a target fails to load.
   Prints A11Y OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"

static NSString *const kSpec =
  @"<column id=\"root\" role=\"group\" a11y-label=\"Preferences\">\n"
  @"  <row><label id=\"themeLabel\" label-for=\"theme\">Theme</label><popup id=\"theme\" items=\"A, B\"/></row>\n"
  @"  <popup id=\"snooze\" a11y-label=\"Snooze\" items=\"Snooze, 1 hour\"/>\n"
  @"  <image id=\"deco\" role=\"none\"/>\n"
  @"  <scroll><column><label id=\"notesLabel\" label-for=\"notes\">Notes</label><field id=\"notes\"/></column></scroll>\n"
  @"</column>\n";

static int gFail = 0;

static void Expect(NSString *what, id got, id want)
{
  BOOL ok = (got == want) || [got isEqual: want];
  printf("%s %s: %s\n", ok ? "ok  " : "FAIL", [what UTF8String], [[got description] UTF8String] ?: "(nil)");
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
      TRMarkupDocument *doc = [TRMarkupDocument documentWithString: kSpec name: @"a11y.trellis" error: &err];
      TRBoxView *box = doc ? [TRLoader loadDocument: doc owner: nil error: &err] : nil;
      if (box == nil) { printf("load failed: %s\n", [[err localizedDescription] UTF8String]); return 2; }
      NSView *theme = [TRLoader viewWithIdentifier: @"theme" inView: box];
      NSView *themeLabel = [TRLoader viewWithIdentifier: @"themeLabel" inView: box];
      NSView *snooze = [TRLoader viewWithIdentifier: @"snooze" inView: box];
      NSView *deco = [TRLoader viewWithIdentifier: @"deco" inView: box];
      NSView *notes = [TRLoader viewWithIdentifier: @"notes" inView: box];

      Expect(@"theme label (via label-for)", TRAccessibilityLabel(theme), @"Theme");
      Expect(@"theme title view", TRAccessibilityTitleView(theme), themeLabel);
      Expect(@"snooze label (a11y-label)", TRAccessibilityLabel(snooze), @"Snooze");
      Expect(@"notes label (label-for in a scroller)", TRAccessibilityLabel(notes), @"Notes");
      Expect(@"root role", TRAccessibilityRole(box), @"group");
      Expect(@"root label", TRAccessibilityLabel(box), @"Preferences");
      Expect(@"deco role", TRAccessibilityRole(deco), @"none");
#ifndef GNUSTEP
      Expect(@"Cocoa: snooze accessibilityLabel", [snooze accessibilityLabel], @"Snooze");
      Expect(@"Cocoa: theme accessibilityTitleUIElement", [theme accessibilityTitleUIElement], themeLabel);
      Expect(@"Cocoa: root accessibilityRole", [box accessibilityRole], NSAccessibilityGroupRole);
      Expect(@"Cocoa: deco isAccessibilityElement", @([deco isAccessibilityElement]), @NO);
#endif

      NSString *bad = @"<column><label label-for=\"nope\">X</label></column>";
      TRMarkupDocument *bd = [TRMarkupDocument documentWithString: bad name: @"bad.trellis" error: NULL];
      err = nil;
      TRBoxView *bb = [TRLoader loadDocument: bd owner: nil error: &err];
      Expect(@"missing label-for target fails to load", @(bb == nil && [[err localizedDescription] rangeOfString: @"label-for=\"nope\""].location != NSNotFound), @YES);

      printf(gFail ? "A11Y FAIL\n" : "A11Y OK\n");
      return gFail ? 1 : 0;
    }
}
