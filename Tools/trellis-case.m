/* trellis-case - runs Trellis layout test cases (docs/test-case-format.md).

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <Foundation/Foundation.h>
#import "TRNode.h"

static BOOL gVerbose = NO;

/* Ahem-style text: every glyph charWidth wide, wraps at spaces. */
static TRSize TRAhemMeasure(NSString *text, TRFloat cw, TRFloat lh,
                            TRSize avail, TRMeasureMode wm)
{
  NSArray *words = [text componentsSeparatedByString: @" "];
  TRFloat maxContent = [text length] * cw;
  if ([text length] == 0) return TRSizeMake(0, 0);
  TRFloat limit = (wm == TRMeasureModeUndefined) ? INFINITY : avail.width;
  if (wm == TRMeasureModeExactly || wm == TRMeasureModeAtMost)
    limit = avail.width;
  TRFloat lineW = 0, maxW = 0;
  int lines = 1;
  for (NSString *w in words)
    {
      TRFloat ww = [w length] * cw;
      if (lineW == 0)
        lineW = ww;
      else if (lineW + cw + ww <= limit + 0.0001)
        lineW += cw + ww;
      else
        {
          maxW = MAX(maxW, lineW);
          lineW = ww;
          lines++;
        }
    }
  maxW = MAX(maxW, lineW);
  if (wm == TRMeasureModeUndefined) maxW = maxContent;
  return TRSizeMake(maxW, lines * lh);
}

static TRNode *TRBuildNode(NSDictionary *d, NSString **err)
{
  NSDictionary *style = d[@"style"] ?: @{};
  NSError *e = nil;
  TRStyle *st = [TRStyle styleWithDictionary: style error: &e];
  if (st == nil)
    {
      *err = [e localizedDescription];
      return nil;
    }
  TRNode *n = [TRNode node];
  n.style = st;
  if (d[@"id"]) n.identifier = d[@"id"];
  NSDictionary *m = d[@"measure"];
  if (m)
    {
      if (m[@"text"])
        {
          NSString *text = m[@"text"];
          TRFloat cw = [m[@"charWidth"] doubleValue] ?: 10;
          TRFloat lh = [m[@"lineHeight"] doubleValue] ?: 10;
          n.measureBlock = ^TRSize(TRSize avail, TRMeasureMode wm, TRMeasureMode hm) {
            return TRAhemMeasure(text, cw, lh, avail, wm);
          };
        }
      else
        {
          TRFloat w = [m[@"width"] doubleValue], h = [m[@"height"] doubleValue];
          n.measureBlock = ^TRSize(TRSize avail, TRMeasureMode wm, TRMeasureMode hm) {
            return TRSizeMake(w, h);
          };
        }
      if (m[@"baseline"])
        {
          TRFloat b = [m[@"baseline"] doubleValue];
          n.baselineBlock = ^TRFloat(TRSize size) { return b; };
        }
    }
  for (NSDictionary *c in d[@"children"])
    {
      TRNode *cn = TRBuildNode(c, err);
      if (cn == nil) return nil;
      [n addChild: cn];
    }
  return n;
}

static void TRCompare(TRNode *n, NSDictionary *exp, NSString *path, TRFloat tol,
                      NSMutableArray *diffs)
{
  TRRect f = [n layoutFrame];
  TRFloat got[4] = { f.x, f.y, f.width, f.height };
  NSString *keys[4] = { @"x", @"y", @"width", @"height" };
  for (int i = 0; i < 4; i++)
    {
      id v = exp[keys[i]];
      if (v == nil) continue;
      if (fabs([v doubleValue] - got[i]) > tol)
        [diffs addObject: [NSString stringWithFormat: @"%@.%@: expected %g, got %g",
                            path, keys[i], [v doubleValue], got[i]]];
    }
  NSArray *ec = exp[@"children"];
  NSArray *kids = [n children];
  if (ec && [ec count] != [kids count])
    {
      [diffs addObject: [NSString stringWithFormat: @"%@: expected %lu children, have %lu",
                          path, (unsigned long)[ec count], (unsigned long)[kids count]]];
      return;
    }
  for (NSUInteger i = 0; i < [ec count]; i++)
    TRCompare(kids[i], ec[i], [NSString stringWithFormat: @"%@/%lu", path, (unsigned long)i],
              tol, diffs);
}

typedef enum { TRPass, TRFail, TRSkip } TROutcome;

static TROutcome TRRunCase(NSString *file, NSDictionary *c, NSString **suiteOut)
{
  NSString *cid = c[@"id"] ?: [file lastPathComponent];
  NSString *suite = c[@"source"][@"suite"];
  if (suite == nil)
    {
      NSArray *parts = [cid componentsSeparatedByString: @"/"];
      suite = [parts count] > 1 ? parts[0] : @"local";
    }
  *suiteOut = suite;
  if (c[@"skip"])
    {
      if (gVerbose) printf("SKIP %s: %s\n", [cid UTF8String], [[c[@"skip"] description] UTF8String]);
      return TRSkip;
    }
  NSString *err = nil;
  TRNode *root = TRBuildNode(c[@"root"], &err);
  if (root == nil)
    {
      printf("FAIL %s: bad style: %s\n", [cid UTF8String], [err UTF8String]);
      return TRFail;
    }
  id ps = c[@"pixelScale"];
  root.pixelScale = ps ? [ps doubleValue] : 1.0;
  NSDictionary *avail = c[@"available"];
  TRFloat aw = TRUndefined, ah = TRUndefined;
  if ([avail[@"width"] isKindOfClass: [NSNumber class]]) aw = [avail[@"width"] doubleValue];
  if ([avail[@"height"] isKindOfClass: [NSNumber class]]) ah = [avail[@"height"] doubleValue];
  TRDirection dir = [c[@"direction"] isEqual: @"rtl"] ? TRDirectionRTL : TRDirectionLTR;
  [root layoutWithAvailableSize: TRSizeMake(aw, ah) direction: dir];
  TRFloat tol = c[@"tolerance"] ? [c[@"tolerance"] doubleValue] : 0.5;
  NSMutableArray *diffs = [NSMutableArray array];
  TRCompare(root, c[@"expected"], @"root", tol, diffs);
  if ([diffs count] == 0)
    {
      if (gVerbose) printf("PASS %s\n", [cid UTF8String]);
      return TRPass;
    }
  printf("FAIL %s (%s)\n", [cid UTF8String], [file UTF8String]);
  NSUInteger shown = 0;
  for (NSString *d in diffs)
    {
      if (++shown > 6) { printf("    ... %lu more\n", (unsigned long)([diffs count] - 6)); break; }
      printf("    %s\n", [d UTF8String]);
    }
  return TRFail;
}

static void TRCollect(NSString *path, NSMutableArray *out)
{
  BOOL isDir = NO;
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath: path isDirectory: &isDir]) return;
  if (!isDir)
    {
      [out addObject: path];
      return;
    }
  NSDirectoryEnumerator *en = [fm enumeratorAtPath: path];
  NSString *rel;
  while ((rel = [en nextObject]) != nil)
    if ([[rel pathExtension] isEqualToString: @"json"])
      [out addObject: [path stringByAppendingPathComponent: rel]];
}

int main(int argc, const char **argv)
{
  @autoreleasepool
    {
      NSMutableArray *files = [NSMutableArray array];
      for (int i = 1; i < argc; i++)
        {
          NSString *a = [NSString stringWithUTF8String: argv[i]];
          if ([a isEqualToString: @"--verbose"] || [a isEqualToString: @"-v"]) gVerbose = YES;
          else TRCollect(a, files);
        }
      [files sortUsingSelector: @selector(compare:)];
      NSUInteger pass = 0, fail = 0, skip = 0;
      NSMutableDictionary *perSuite = [NSMutableDictionary dictionary];
      for (NSString *f in files)
        {
          NSData *data = [NSData dataWithContentsOfFile: f];
          id json = data ? [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL] : nil;
          NSArray *cases = [json isKindOfClass: [NSArray class]] ? json : (json ? @[json] : nil);
          if (cases == nil)
            {
              printf("FAIL %s: unreadable JSON\n", [f UTF8String]);
              fail++;
              continue;
            }
          for (NSDictionary *c in cases)
            {
              NSString *suite = @"local";
              TROutcome o;
              @try { o = TRRunCase(f, c, &suite); }
              @catch (NSException *ex)
                {
                  printf("FAIL %s: exception %s\n", [f UTF8String], [[ex reason] UTF8String]);
                  o = TRFail;
                }
              NSMutableArray *t = perSuite[suite];
              if (t == nil) perSuite[suite] = t = [NSMutableArray arrayWithObjects: @0, @0, @0, nil];
              t[o] = @([t[o] unsignedIntegerValue] + 1);
              if (o == TRPass) pass++; else if (o == TRFail) fail++; else skip++;
            }
        }
      NSUInteger run = pass + fail;
      printf("PASS %lu/%lu (%.1f%%)  fail %lu  skip %lu\n", (unsigned long)pass,
             (unsigned long)run, run ? 100.0 * pass / run : 100.0,
             (unsigned long)fail, (unsigned long)skip);
      for (NSString *s in [[perSuite allKeys] sortedArrayUsingSelector: @selector(compare:)])
        {
          NSArray *t = perSuite[s];
          NSUInteger p = [t[0] unsignedIntegerValue], fl = [t[1] unsignedIntegerValue];
          printf("  %s: %lu/%lu (%.1f%%)\n", [s UTF8String], (unsigned long)p,
                 (unsigned long)(p + fl), (p + fl) ? 100.0 * p / (p + fl) : 100.0);
        }
      return fail ? 1 : 0;
    }
}
