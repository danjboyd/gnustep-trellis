/* trellis-lint - checks frames.json files written by trellis-render.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <Foundation/Foundation.h>
#import "TRLint.h"

int main(int argc, const char **argv)
{
  @autoreleasepool
    {
      if (argc < 2)
        {
          fprintf(stderr, "usage: trellis-lint frames.json...\n");
          return 2;
        }
      int errors = 0, warnings = 0;
      for (int i = 1; i < argc; i++)
        {
          NSString *path = [NSString stringWithUTF8String: argv[i]];
          NSData *data = [NSData dataWithContentsOfFile: path];
          NSDictionary *doc = data ? [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL] : nil;
          if (![doc isKindOfClass: [NSDictionary class]] || doc[@"root"] == nil)
            {
              fprintf(stderr, "%s: not a Trellis frame dump\n", argv[i]);
              errors++;
              continue;
            }
          NSDictionary *vp = doc[@"viewport"];
          NSArray *found = TRLintFrameTree(doc[@"root"], [vp[@"width"] doubleValue],
                                           [vp[@"height"] doubleValue]);
          for (NSDictionary *f in found)
            {
              BOOL err = [f[@"severity"] isEqualToString: @"error"];
              if (err) errors++; else warnings++;
              printf("%s: %s [%s] %s\n", argv[i], [f[@"severity"] UTF8String],
                     [f[@"rule"] UTF8String], [f[@"message"] UTF8String]);
            }
        }
      printf("%d error(s), %d warning(s)\n", errors, warnings);
      return errors ? 1 : 0;
    }
}
