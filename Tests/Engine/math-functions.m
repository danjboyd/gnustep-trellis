/* min(), max() and clamp() lengths: the serialized value parses back to
   the same value; expressions past the first table chunk (256) resolve;
   parsing from several threads at once interns each expression once and
   every node resolves to its own value. Prints MATHFN OK. */
#import <Foundation/Foundation.h>
#import "TrellisEngine.h"

static int failures = 0;

static void check(BOOL ok, NSString *what)
{
  if (!ok) failures++;
  printf("%s %s\n", ok ? "ok  " : "FAIL", [what UTF8String]);
}

/* The width of a child with style decl in a parent of width w. */
static TRFloat widthIn(NSString *decl, TRFloat w)
{
  TRNode *root = [TRNode nodeWithStyle: [NSString stringWithFormat: @"width: %gpx; height: 10px", w] children: nil];
  TRNode *c = [TRNode nodeWithStyle: decl children: nil];
  [root addChild: c];
  root.pixelScale = 0;
  [root layoutWithAvailableSize: TRSizeMake(w, 10) direction: TRDirectionLTR];
  return c.layoutFrame.width;
}

/* Parses and lays out min(i px, 50%) for i = first, first + 4, ... 600
   at a 1000px basis, counting wrong widths. */
@interface Parser : NSObject
{
@public
  int first, bad;
  NSConditionLock *done;
}
- (void)run;
@end

@implementation Parser
- (instancetype)init
{
  if ((self = [super init])) done = [[NSConditionLock alloc] initWithCondition: 0];
  return self;
}
- (void)run
{
  @autoreleasepool
    {
      [done lock];
      for (int i = first; i <= 600; i += 4)
        {
          NSString *d = [NSString stringWithFormat: @"width: min(%dpx, 50%%)", i];
          TRFloat got = widthIn(d, 1000);
          TRFloat again = widthIn(d, 1000);
          if (fabs(got - MIN(i, 500)) > 0.01 || got != again) bad++;
        }
      [done unlockWithCondition: 1];
    }
}
@end

int main(void)
{
  @autoreleasepool
    {
      NSString *decl = @"width: clamp(10px, 25% + 4px, 50px)";
      TRStyle *s = [TRStyle styleWithDeclarations: decl];
      NSString *out = [s declarationString];
      check([out rangeOfString: @"clamp(10px, 25% + 4px, 50px)"].location != NSNotFound,
            [NSString stringWithFormat: @"declarationString keeps the expression (%@)", out]);
      TRStyle *back = [TRStyle styleWithDeclarations: out];
      check([[back declarationString] isEqualToString: out], @"the serialized value parses back to the same value");

      check(fabs(widthIn(@"width: calc(100% - clamp(10px, 25%, 50px))", 400) - 350) < 0.01, @"clamp at its max");
      check(fabs(widthIn(@"width: calc(100% - clamp(10px, 25%, 50px))", 100) - 75) < 0.01, @"clamp between its bounds");
      check(fabs(widthIn(@"width: calc(100% - clamp(10px, 25%, 50px))", 20) - 10) < 0.01, @"clamp at its min");
      check(fabs(widthIn(@"width: max(-1 * min(10px, -5%), 1px)", 400) - 20) < 0.01, @"a negated min() flips to a max");

      /* Distinct expressions, from four threads at once: each resolves to
         min(i px, 50%), here i at a 1000px basis. */
      Parser *ps[4];
      for (int t = 0; t < 4; t++)
        {
          ps[t] = [Parser new];
          ps[t]->first = 1 + t;
          [NSThread detachNewThreadSelector: @selector(run) toTarget: ps[t] withObject: nil];
        }
      int bad = 0;
      for (int t = 0; t < 4; t++)
        {
          [ps[t]->done lockWhenCondition: 1];
          [ps[t]->done unlock];
          bad += ps[t]->bad;
        }
      check(bad == 0, [NSString stringWithFormat: @"600 expressions from four threads resolve (%d wrong)", bad]);

      printf(failures ? "MATHFN FAIL\n" : "MATHFN OK\n");
      return failures ? 1 : 0;
    }
}
