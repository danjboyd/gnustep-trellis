/* calc() parses the same under a decimal-comma C locale: an app may call
   setlocale, and strtod would then stop at the '.' of 10.5px. Picks the
   first installed locale whose decimal point is ',', or prints
   CALCLOCALE SKIP when there is none. Prints CALCLOCALE OK. */
#import <Foundation/Foundation.h>
#import <locale.h>
#import "TrellisEngine.h"

int main(void)
{
  @autoreleasepool
    {
      const char *names[] = { "de_DE.UTF-8", "de_DE.utf8", "fr_FR.UTF-8", "fr_FR.utf8",
                              "nl_NL.UTF-8", "es_ES.UTF-8", "German_Germany.1252", NULL };
      const char *got = NULL;
      for (int i = 0; names[i]; i++)
        if (setlocale(LC_ALL, names[i]) && strcmp(localeconv()->decimal_point, ",") == 0)
          { got = names[i]; break; }
      if (got == NULL) { printf("CALCLOCALE SKIP (no decimal-comma locale installed)\n"); return 0; }
      TRNode *root = [TRNode nodeWithStyle: @"width: 100px; height: 20px" children: nil];
      TRNode *c = [TRNode nodeWithStyle: @"width: calc(50% - 10.5px); margin-left: calc(2.5px)" children: nil];
      [root addChild: c];
      [root layoutWithAvailableSize: TRSizeMake(100, 20) direction: TRDirectionLTR];
      TRRect f = c.layoutFrame;
      BOOL ok = fabs(f.width - 39.5) < 0.01 && fabs(f.x - 2.5) < 0.01;
      printf("%s calc under %s: x %g width %g\n", ok ? "ok  " : "FAIL", got, f.x, f.width);
      printf(ok ? "CALCLOCALE OK\n" : "CALCLOCALE FAIL\n");
      return ok ? 0 : 1;
    }
}
