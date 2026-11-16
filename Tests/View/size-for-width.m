/* Headless check of the TRSizeForWidth hook: a view whose height depends on
   its width is measured in one pass. Build against obj/ and run under
   scripts/run-headless.sh; prints HOOK OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRViewMeasure.h"
@interface HFW : NSView <TRSizeForWidth>
@property (nonatomic) int calls;
@end
@implementation HFW
- (NSSize)trellisSizeForWidth:(CGFloat)w
{
  self.calls++;
  if (w >= 1e30) return NSMakeSize(400, 10);         /* max-content: one line */
  return NSMakeSize(w, ceil(1000.0 / MAX(w, 1)));    /* height grows as width shrinks */
}
@end
int main(void)
{
  @autoreleasepool {
    [NSApplication sharedApplication];
    TRBoxView *col = [TRBoxView boxWithStyle: @"flex-direction: column; align-items: stretch"];
    HFW *v = [[HFW alloc] initWithFrame: NSZeroRect];
    [col addSubview: v];
    int ok = 1;
    for (int i = 0; i < 2; i++)
      {
        CGFloat W = i == 0 ? 100 : 50;
        [col setFrame: NSMakeRect(0, 0, W, 400)];
        [col layoutTrellis];
        NSRect f = [v frame];
        printf("W=%g -> view %gx%g (calls so far %d)\n", W, f.size.width, f.size.height, v.calls);
        if (f.size.width != W || f.size.height != ceil(1000.0 / W)) ok = 0;
      }
    printf(ok ? "HOOK OK\n" : "HOOK FAIL\n");
    return ok ? 0 : 1;
  }
}
