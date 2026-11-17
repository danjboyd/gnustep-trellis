/* Markup parsing scales linearly: 8x the elements takes well under 64x
   the time (it was quadratic: every element's line and column were
   counted from the start of the file). Line and column numbers stay
   right, for elements and for errors. Prints MARKUPSCALE OK. */
#import <Foundation/Foundation.h>
#import "TRMarkup.h"

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok) gFail++;
}

static NSString *Rows(NSUInteger n)
{
  NSMutableString *s = [NSMutableString stringWithString: @"<column>\n"];
  for (NSUInteger i = 0; i < n; i++)
    [s appendFormat: @"  <row><label>Item %lu</label><field id=\"f%lu\" placeholder=\"Value\"/><button>Go</button></row>\n",
       (unsigned long)i, (unsigned long)i];
  [s appendString: @"</column>\n"];
  return s;
}

/* Best of three, in ms. */
static double ParseTime(NSString *src)
{
  double best = 1e9;
  for (int k = 0; k < 3; k++)
    {
      @autoreleasepool
        {
          NSDate *t = [NSDate date];
          TRMarkupDocument *d = [TRMarkupDocument documentWithString: src name: @"scale.trellis" error: NULL];
          double ms = -[t timeIntervalSinceNow] * 1000;
          if (d == nil) return -1;
          if (ms < best) best = ms;
        }
    }
  return best;
}

int main(void)
{
  @autoreleasepool
    {
      NSString *small = Rows(500), *large = Rows(4000);
      double ts = ParseTime(small), tl = ParseTime(large);
      printf("     500 rows: %.1f ms, 4000 rows: %.1f ms (x%.1f)\n", ts, tl, ts > 0 ? tl / ts : 0);
      Expect("both parse", ts >= 0 && tl >= 0);
      /* Linear is about x8; quadratic was about x64. Allow noise. */
      Expect("8x the rows takes less than 24x the time", tl < 24 * MAX(ts, 0.5));

      TRMarkupDocument *d = [TRMarkupDocument documentWithString: large name: @"scale.trellis" error: NULL];
      TRMarkupElement *last = nil;
      for (TRMarkupElement *e in [d allElements]) if ([[e identifier] isEqualToString: @"f3999"]) last = e;
      printf("     f3999 at %lu:%lu\n", (unsigned long)last.line, (unsigned long)last.column);
      Expect("line and column of the last field", last.line == 4001 && last.column == 32);

      NSError *err = nil;
      NSString *bad = [Rows(50) stringByAppendingString: @"<oops\n"];
      [TRMarkupDocument documentWithString: bad name: @"bad.trellis" error: &err];
      printf("     error: %s\n", [[err localizedDescription] UTF8String]);
      Expect("an error late in the file has its line", [[err localizedDescription] rangeOfString: @":54:1"].location != NSNotFound);
    }
  printf(gFail ? "MARKUPSCALE FAIL (%d)\n" : "MARKUPSCALE OK\n", gFail);
  return gFail ? 1 : 0;
}
