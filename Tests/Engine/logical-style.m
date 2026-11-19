/* Logical sides in TRStyle: declarationString writes them back as logical
   sides, so a style read back from its string lays out the same in rtl;
   -copy keeps them; typed setters after a logical side override it in
   both directions. Prints LOGICALSTYLE OK. */
#import <Foundation/Foundation.h>
#import "TrellisEngine.h"

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok) gFail++;
}

/* x of a 20px-wide child with the given style in a 100px row. */
static double ChildX(TRStyle *st, TRDirection dir)
{
  TRNode *root = [TRNode nodeWithStyle: @"width: 100px; height: 20px" children: nil];
  TRNode *c = [TRNode node];
  c.style = st;
  [root addChild: c];
  [root layoutWithAvailableSize: TRSizeMake(100, 20) direction: dir];
  return c.layoutFrame.x;
}

int main(void)
{
  @autoreleasepool
    {
      TRStyle *s = [TRStyle styleWithDeclarations: @"width: 20px; margin-inline-start: 10px; padding-left: 3px"];
      NSString *str = [s declarationString];
      Expect("logical side written as logical", [str rangeOfString: @"margin-inline-start: 10px"].location != NSNotFound);
      Expect("physical side written as physical", [str rangeOfString: @"padding-left: 3px"].location != NSNotFound);
      Expect("no margin-left in the string", [str rangeOfString: @"margin-left"].location == NSNotFound);
      TRStyle *back = [TRStyle styleWithDeclarations: str];
      Expect("ltr x 10", ChildX(s, TRDirectionLTR) == 10);
      Expect("rtl x 70", ChildX(s, TRDirectionRTL) == 70);
      Expect("read back: rtl x 70", ChildX(back, TRDirectionRTL) == 70);
      Expect("copy: rtl x 70", ChildX([s copy], TRDirectionRTL) == 70);

      TRStyle *t = [TRStyle styleWithDeclarations: @"width: 20px; margin-inline-start: 10px"];
      [t setMargin: TRPx(4) forEdge: TREdgeRight];
      Expect("setMargin:forEdge: after a logical side: rtl right margin 4", ChildX(t, TRDirectionRTL) == 76);
      [t setMargin: TRPx(0)];
      Expect("setMargin: clears both directions", ChildX(t, TRDirectionRTL) == 80 && ChildX(t, TRDirectionLTR) == 0);

      TRStyle *u = [TRStyle styleWithDeclarations: @"width: 20px; margin-inline: 6px 2px"];
      Expect("margin-inline written as start/end",
             [[u declarationString] rangeOfString: @"margin-inline-end: 2px"].location != NSNotFound);
      /* Overflow alignment on self-alignment survives declarationString. */
      TRStyle *sa = [TRStyle styleWithDeclarations:
        @"justify-items: safe center; align-self: safe end; justify-self: unsafe end; align-items: center"];
      NSString *sas = [sa declarationString];
      Expect("justify-items keeps safe", [sas rangeOfString: @"justify-items: safe center"].location != NSNotFound);
      Expect("align-self keeps safe", [sas rangeOfString: @"align-self: safe end"].location != NSNotFound);
      Expect("unsafe is the default, written plain", [sas rangeOfString: @"justify-self: end"].location != NSNotFound
             && [sas rangeOfString: @"unsafe"].location == NSNotFound);
      Expect("safe read back", [[[TRStyle styleWithDeclarations: sas] declarationString] isEqualToString: sas]);
      printf("%s\n", gFail ? "LOGICALSTYLE FAIL" : "LOGICALSTYLE OK");
    }
  return gFail ? 1 : 0;
}
