/* Rich text in labels (headless): <b>, <i>, <code>, <br> and links;
   whitespace collapsing across runs; the style's font and colour under
   the runs; clicking a link sends its action to the owner; an action the
   owner lacks is a load error. Prints RICHTEXT OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"

static NSString *const kSpec =
  @"<column>\n"
  @"  <text id=\"note\" class=\"note\">Ticket <a action=\"openTicket:\" href=\"482\">#482</a> is <b>blocked</b>\n"
  @"    on <i>review</i>; run <code>make check</code>.<br/>See <a href=\"https://example.com/guide\">the guide</a>.</text>\n"
  @"  <label id=\"plain\">No markup here</label>\n"
  @"</column>\n"
  @"<style> .note { font-size: 15px; color: GrayText; } </style>\n";

@interface Owner : NSObject
{
@public
  NSString *opened;
  id sender;
}
- (void)openTicket:(id)sender;
@end
@implementation Owner
- (void)openTicket:(id)s { sender = s; opened = [(TRRichLabel *)s clickedLink]; }
@end

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
      Owner *owner = [Owner new];
      NSError *err = nil;
      TRMarkupDocument *doc = [TRMarkupDocument documentWithString: kSpec name: @"rich.trellis" error: &err];
      TRBoxView *root = doc ? [TRLoader loadDocument: doc owner: nil error: &err] : nil;
      if (root == nil) { printf("load failed: %s\n", [[err localizedDescription] UTF8String]); return 2; }
      /* Bind links to the owner (no outlets in this spec). */
      TRRichLabel *note = (TRRichLabel *)[TRLoader viewWithIdentifier: @"note" inView: root];
      Expect("<text> with inline markup is a TRRichLabel", [note isKindOfClass: [TRRichLabel class]]);
      Expect("a plain label stays a plain text field",
             ![[TRLoader viewWithIdentifier: @"plain" inView: root] isKindOfClass: [TRRichLabel class]]);
      note.linkTarget = owner;
      NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 420, 200)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered defer: YES];
      [win setReleasedWhenClosed: NO];
      [win setContentView: root];
      [root layoutTrellis];

      NSString *plain = [note plainText];
      printf("     text: \"%s\"\n", [[plain stringByReplacingOccurrencesOfString: @"\n" withString: @"\\n"] UTF8String]);
      Expect("whitespace collapses across runs, <br> breaks the line",
             [plain isEqualToString: @"Ticket #482 is blocked on review; run make check.\nSee the guide."]);
      NSAttributedString *s = [note attributedStringValue];
      NSRange rb = [[s string] rangeOfString: @"blocked"], ri = [[s string] rangeOfString: @"review"];
      NSRange rc = [[s string] rangeOfString: @"make check"], rl = [[s string] rangeOfString: @"#482"];
      NSFontManager *fm = [NSFontManager sharedFontManager];
      NSFont *fb = [s attribute: NSFontAttributeName atIndex: rb.location effectiveRange: NULL];
      NSFont *fi = [s attribute: NSFontAttributeName atIndex: ri.location effectiveRange: NULL];
      NSFont *fc = [s attribute: NSFontAttributeName atIndex: rc.location effectiveRange: NULL];
      NSFont *f0 = [s attribute: NSFontAttributeName atIndex: 0 effectiveRange: NULL];
      Expect("<b> is bold", ([fm traitsOfFont: fb] & NSBoldFontMask) != 0);
      Expect("<i> is italic (or slanted when no italic face is installed)",
             ([fm traitsOfFont: fi] & NSItalicFontMask) != 0
             || [[s attribute: NSObliquenessAttributeName atIndex: ri.location effectiveRange: NULL] doubleValue] > 0);
      Expect("<code> is fixed pitch", [fc isFixedPitch] || ![[fc familyName] isEqualToString: [f0 familyName]]);
      Expect("runs take the style's font size", fabs([f0 pointSize] - 15) < 0.01 && fabs([fb pointSize] - 15) < 0.01);
      NSColor *c0 = [s attribute: NSForegroundColorAttributeName atIndex: 0 effectiveRange: NULL];
      NSColor *cl = [s attribute: NSForegroundColorAttributeName atIndex: rl.location effectiveRange: NULL];
      Expect("text takes the style's colour, links LinkText", c0 != nil && cl != nil && ![c0 isEqual: cl]);
      Expect("links are underlined and carry their href",
             [[s attribute: NSUnderlineStyleAttributeName atIndex: rl.location effectiveRange: NULL] integerValue] != 0
             && [[s attribute: NSLinkAttributeName atIndex: rl.location effectiveRange: NULL] isEqual: @"482"]);

      /* Hit testing: the middle of the first link's run, and plain text. */
      NSRect lr = [note rectForLinkAtRun: 1];
      NSUInteger hit = [note linkIndexAtPoint: NSMakePoint(NSMidX(lr), NSMidY(lr))];
      printf("     link rect %.0f,%.0f %.0fx%.0f, hit %lu\n", lr.origin.x, lr.origin.y, lr.size.width, lr.size.height,
             (unsigned long)hit);
      Expect("a point on the link finds it", hit != NSNotFound && NSLocationInRange(hit, rl));
      NSRect tr = [note rectForLinkAtRun: 0];
      Expect("plain text is not a link", [note linkIndexAtPoint: NSMakePoint(NSMinX(tr) + 2, NSMidY(tr))] == NSNotFound);
      Expect("following the link sends its action to the target", [note activateLinkAtCharacterIndex: hit]
             && [owner->opened isEqualToString: @"482"] && owner->sender == note);

      /* A missing action is a load error naming it. */
      TRMarkupDocument *bad = [TRMarkupDocument documentWithString:
        @"<column><label>See <a action=\"nope:\">this</a></label></column>" name: @"bad.trellis" error: &err];
      TRBoxView *br = [TRLoader loadDocument: bad owner: owner error: &err];
      Expect("an <a action> the owner lacks is a load error",
             br == nil && [[err localizedDescription] rangeOfString: @"nope:"].location != NSNotFound);
      [win close];
    }
  printf(gFail ? "RICHTEXT FAIL\n" : "RICHTEXT OK\n");
  return gFail ? 1 : 0;
}
