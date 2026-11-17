/* <split> (headless): panes sized from their CSS (starting size, limits,
   flex-grow on resize), divider positions set in code and clamped, kept
   across loads with autosave=, stacked panes, the Tab loop through the
   panes, and load errors. Prints SPLIT OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"
#import "TRSplitView.h"

static NSString *const kSpec =
  @"<column>\n"
  @"  <split id=\"main\" autosave=\"split-test\">\n"
  @"    <column id=\"side\" class=\"side\"><button id=\"b1\">One</button></column>\n"
  @"    <column id=\"body\" class=\"body\"><button id=\"b2\">Two</button>\n"
  @"      <split id=\"stack\" direction=\"column\">\n"
  @"        <box id=\"top\" class=\"top\"><label>Top</label></box>\n"
  @"        <box id=\"bottom\"><button id=\"b3\">Three</button></box>\n"
  @"      </split>\n"
  @"    </column>\n"
  @"  </split>\n"
  @"</column>\n"
  @"<style>\n"
  @"  .side { width: 200px; min-width: 120px; max-width: 300px; padding: 8px; }\n"
  @"  .body { flex-grow: 1; }\n"
  @"  .top { height: 100px; min-height: 60px; }\n"
  @"</style>\n";

@interface Owner : NSObject
{
@public
  int dragged;
}
- (void)splitMoved:(id)sender;
@end
@implementation Owner
- (void)splitMoved:(id)sender { dragged++; }
@end

static NSEvent *Mouse(NSEventType type, NSWindow *win, NSPoint p)
{
  return [NSEvent mouseEventWithType: type location: p modifierFlags: 0 timestamp: 0
                        windowNumber: [win windowNumber] context: nil eventNumber: 0
                          clickCount: 1 pressure: 1];
}

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  fflush(stdout);
  if (!ok) gFail++;
}

static TRBoxView *Load(NSString *spec, NSError **err)
{
  TRMarkupDocument *doc = [TRMarkupDocument documentWithString: spec name: @"split.trellis" error: err];
  return doc ? [TRLoader loadDocument: doc owner: nil error: err] : nil;
}

int main(void)
{
  @autoreleasepool
    {
#ifdef GNUSTEP
      [NSApplication sharedApplication];
#endif
      NSString *key = @"TRSplitView Panes split-test";
      [[NSUserDefaults standardUserDefaults] removeObjectForKey: key];
      NSError *err = nil;
      TRBoxView *root = Load(kSpec, &err);
      if (root == nil) { printf("load failed: %s\n", [[err localizedDescription] UTF8String]); return 2; }
      NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 800, 400)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered defer: NO];
      [win setReleasedWhenClosed: NO];
      [win setContentView: root];
      [root setFrame: NSMakeRect(0, 0, 800, 400)];
      [root layoutTrellis];
      TRSplitView *split = (TRSplitView *)[TRLoader viewWithIdentifier: @"main" inView: root];
      TRBoxView *side = (TRBoxView *)[TRLoader viewWithIdentifier: @"side" inView: root];
      NSView *body = [TRLoader viewWithIdentifier: @"body" inView: root];
      CGFloat thick = [split dividerThickness];
      Expect("<split> is a TRSplitView", [split isKindOfClass: [TRSplitView class]]);
      Expect("the split fills its column", NSWidth([split frame]) == 800 && NSHeight([split frame]) == 400);
      printf("     side %.0f, body %.0f, divider %.0f\n", NSWidth([side frame]), NSWidth([body frame]), thick);
      Expect("a pane's width is its starting size", NSWidth([side frame]) == 200);
      Expect("the other pane takes the rest", fabs(NSWidth([body frame]) - (800 - 200 - thick)) < 1);
      Expect("panes fill the split's height", NSHeight([side frame]) == 400);
      NSView *b1 = [TRLoader viewWithIdentifier: @"b1" inView: root];
      Expect("a pane lays out its content at the split's size (padding 8)",
             fabs(NSWidth([b1 frame]) - (200 - 16)) < 1);
      Expect("dividerPositions", [[split dividerPositions] isEqual: @[@200]]);

      [root setFrame: NSMakeRect(0, 0, 1000, 400)];
      [root layoutTrellis];
      Expect("growing the split grows the flex-grow pane only",
             NSWidth([side frame]) == 200 && fabs(NSWidth([body frame]) - (1000 - 200 - thick)) < 1);

      [split setDividerPositions: @[@50]];
      Expect("a divider can't go below the pane's min-width", NSWidth([side frame]) == 120);
      [split setDividerPositions: @[@600]];
      Expect("nor above its max-width", NSWidth([side frame]) == 300);
      [split setDividerPositions: @[@250]];
      Expect("setDividerPositions: moves it", NSWidth([side frame]) == 250
             && NSWidth([b1 frame]) == 250 - 16);
      Expect("drag limits come from min/max",
             [split splitView: split constrainSplitPosition: 10 ofSubviewAt: 0] == 120
             && [split splitView: split constrainSplitPosition: 900 ofSubviewAt: 0] == 300);
      NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey: key];
      Expect("autosave stores the pane sizes", [saved count] == 2 && [saved[0] intValue] == 250);

      /* A real drag: down on the divider, drag far left, up. The drag
         stops at min-width; the result is saved and the action sent. */
      {
        Owner *owner = [Owner new];
        split.target = owner;
        split.action = @selector(splitMoved:);
        [win orderFront: nil];
        [root display];
        CGFloat divX = NSMaxX([side frame]) + thick / 2;
        NSPoint at = [split convertPoint: NSMakePoint(divX, 200) toView: nil];
        NSPoint to = NSMakePoint(at.x - 200, at.y);
        [NSApp postEvent: Mouse(NSEventTypeLeftMouseDragged, win, to) atStart: NO];
        [NSApp postEvent: Mouse(NSEventTypeLeftMouseUp, win, to) atStart: NO];
        [split mouseDown: Mouse(NSEventTypeLeftMouseDown, win, at)];
        printf("     after drag: side %.0f\n", NSWidth([side frame]));
        Expect("dragging the divider stops at the pane's min-width", NSWidth([side frame]) == 120);
        Expect("the drag sends the split's action", owner->dragged == 1);
        Expect("the drag is saved", [[[NSUserDefaults standardUserDefaults] arrayForKey: key][0] intValue] == 120);
        [root setFrame: NSMakeRect(0, 0, 1100, 400)];
        [root layoutTrellis];
        Expect("after a drag, resizing keeps the dragged size", NSWidth([side frame]) == 120);
        [split setDividerPositions: @[@250]];
      }

      /* Stacked panes. */
      TRSplitView *stack = (TRSplitView *)[TRLoader viewWithIdentifier: @"stack" inView: root];
      NSView *top = [TRLoader viewWithIdentifier: @"top" inView: root];
      NSView *bottom = [TRLoader viewWithIdentifier: @"bottom" inView: root];
      printf("     stack %.0fx%.0f, top %.0f, bottom %.0f at y %.0f\n", NSWidth([stack frame]), NSHeight([stack frame]),
             NSHeight([top frame]), NSHeight([bottom frame]), NSMinY([bottom frame]));
      Expect("direction=column stacks the panes (first on top)",
             NSHeight([top frame]) == 100 && NSMinY([top frame]) == 0
             && NSMinY([bottom frame]) >= 100 && NSWidth([top frame]) == NSWidth([stack frame]));
      Expect("the stacked split fills the rest of its column", NSHeight([stack frame]) > 300);

      /* Tab goes through the panes in order. */
      NSView *b2 = [TRLoader viewWithIdentifier: @"b2" inView: root];
      NSView *b3 = [TRLoader viewWithIdentifier: @"b3" inView: root];
      [root recalculateTrellisKeyViewLoop];
      Expect("key loop: b1 -> b2 -> b3", root.firstKeyView == b1 && [b1 nextKeyView] == b2 && [b2 nextKeyView] == b3);

      /* A second load restores the saved position. */
      TRBoxView *root2 = Load(kSpec, &err);
      [root2 setFrame: NSMakeRect(0, 0, 800, 400)];
      [root2 layoutTrellis];
      NSView *side2 = [TRLoader viewWithIdentifier: @"side" inView: root2];
      Expect("autosave restores the pane sizes on the next load", NSWidth([side2 frame]) == 250);

      /* Errors. */
      Expect("direction=\"diagonal\" is an error",
             Load(@"<column><split direction=\"diagonal\"><box/></split></column>", &err) == nil);
      Expect("an empty <split> is an error", Load(@"<column><split></split></column>", &err) == nil);
      Expect("divider=\"wavy\" is an error",
             Load(@"<column><split divider=\"wavy\"><box/></split></column>", &err) == nil);
      [[NSUserDefaults standardUserDefaults] removeObjectForKey: key];
    }
  printf(gFail ? "SPLIT FAIL (%d)\n" : "SPLIT OK\n", gFail);
  return gFail ? 1 : 0;
}
