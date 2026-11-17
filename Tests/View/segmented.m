/* <segmented> (headless): items from <item> children or items=, the
   selection (selected=, <item selected>), tracking modes, a size that
   fits every label in the bold face too, the action reaching the owner,
   sample-file selection, and load errors. Prints SEGMENTED OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"

static NSString *const kSpec =
  @"<row>\n"
  @"  <segmented id=\"mode\" action=\"modeChanged:\" selected=\"Table\"><item>Tiles</item><item>Table</item></segmented>\n"
  @"  <segmented id=\"filter\" tracking=\"any\" items=\"Working, Waiting, Idle\"/>\n"
  @"  <segmented id=\"tools\" tracking=\"momentary\"><item>Cut</item><item>Copy</item></segmented>\n"
  @"</row>\n";

@interface Owner : NSObject
{
@public
  int changed;
  id sender;
}
@property (nonatomic, strong) TRSegmentedControl *mode, *filter, *tools;
- (void)modeChanged:(id)sender;
@end
@implementation Owner
- (void)modeChanged:(id)s { changed++; sender = s; }
@end

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  fflush(stdout);
  if (!ok) gFail++;
}

static TRBoxView *Load(NSString *spec, id owner, NSError **err)
{
  TRMarkupDocument *doc = [TRMarkupDocument documentWithString: spec name: @"seg.trellis" error: err];
  return doc ? [TRLoader loadDocument: doc owner: owner error: err] : nil;
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
      TRBoxView *root = Load(kSpec, owner, &err);
      if (root == nil) { printf("load failed: %s\n", [[err localizedDescription] UTF8String]); return 2; }
      NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 600, 60)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered defer: NO];
      [win setReleasedWhenClosed: NO];
      [win setContentView: root];
      [root setFrame: NSMakeRect(0, 0, 600, 60)];
      [root layoutTrellis];
      TRSegmentedControl *mode = owner.mode, *filter = owner.filter, *tools = owner.tools;
      Expect("<segmented> is a TRSegmentedControl bound to the outlet", [mode isKindOfClass: [TRSegmentedControl class]]);
      Expect("<item> children are the segments", [mode segmentCount] == 2 && [[mode labelForSegment: 1] isEqualToString: @"Table"]);
      Expect("items= works too", [filter segmentCount] == 3 && [[filter labelForSegment: 2] isEqualToString: @"Idle"]);
      Expect("selected= selects by title", [mode selectedSegment] == 1 && [mode.selectedTitles isEqual: @[@"Table"]]);
      Expect("tracking defaults to one", [[mode cell] trackingMode] == NSSegmentSwitchTrackingSelectOne);
      Expect("tracking=any", [[filter cell] trackingMode] == NSSegmentSwitchTrackingSelectAny);
      Expect("tracking=momentary", [[tools cell] trackingMode] == NSSegmentSwitchTrackingMomentary);
      Expect("a momentary control holds no selection", [tools selectedSegment] == -1);

      /* Every segment fits its label, in bold too. */
      NSFont *bold = [[NSFontManager sharedFontManager] convertFont: [filter font] toHaveTrait: NSBoldFontMask];
      CGFloat need = [@"Working" sizeWithAttributes: @{NSFontAttributeName: bold ?: [filter font]}].width;
      printf("     filter %.0f wide, 'Working' needs %.0f per segment\n", NSWidth([filter frame]), need);
      Expect("each segment is wide enough for the longest label", NSWidth([filter frame]) / 3 >= need + 8);
      Expect("segmented controls don't overlap",
             NSMaxX([mode frame]) <= NSMinX([filter frame]) && NSMaxX([filter frame]) <= NSMinX([tools frame]));

      /* The action reaches the owner. */
      [mode setSelectedSegment: 0];
      [mode sendAction: [mode action] to: [mode target]];
      Expect("the action reaches the owner", owner->changed == 1 && owner->sender == mode
             && [mode.selectedTitles isEqual: @[@"Tiles"]]);

      /* selectedTitles in code and in a sample file. */
      filter.selectedTitles = @[@"Working", @"Idle"];
      Expect("selectedTitles selects several (tracking=any)",
             [filter isSelectedForSegment: 0] && ![filter isSelectedForSegment: 1] && [filter isSelectedForSegment: 2]);
      Expect("sample: a title selects it",
             [TRLoader applySample: @{@"mode": @{@"selected": @"Table"}} toView: root error: &err]
             && [mode selectedSegment] == 1);
      Expect("sample: a list of titles",
             [TRLoader applySample: @{@"filter": @{@"selected": @[@"Waiting"]}} toView: root error: &err]
             && [filter.selectedTitles isEqual: @[@"Waiting"]]);

      /* Errors. */
      Expect("no items is an error", Load(@"<row><segmented/></row>", nil, &err) == nil);
      Expect("a non-item child is an error",
             Load(@"<row><segmented><label>x</label></segmented></row>", nil, &err) == nil);
      Expect("tracking=\"many\" is an error",
             Load(@"<row><segmented tracking=\"many\" items=\"A, B\"/></row>", nil, &err) == nil);
      Expect("selected= naming no item is an error",
             Load(@"<row><segmented items=\"A, B\" selected=\"C\"/></row>", nil, &err) == nil);
      Expect("selected under tracking=momentary is an error (AppKit keeps none)",
             Load(@"<row><segmented tracking=\"momentary\"><item selected=\"yes\">A</item><item>B</item></segmented></row>", nil, &err) == nil);
      Expect("<item selected=yes> selects it",
             Load(@"<row><segmented id=\"s\" no-outlet=\"yes\"><item>A</item><item selected=\"yes\">B</item></segmented></row>", nil, &err) != nil);
      Expect("two selected under tracking=one is an error",
             Load(@"<row><segmented><item selected=\"yes\">A</item><item selected=\"yes\">B</item></segmented></row>", nil, &err) == nil);
    }
  printf(gFail ? "SEGMENTED FAIL (%d)\n" : "SEGMENTED OK\n", gFail);
  return gFail ? 1 : 0;
}
