/* trellis-case - runs Trellis layout test cases (docs/test-case-format.md).

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <Foundation/Foundation.h>
#import "TRNode.h"

static BOOL gVerbose = NO;

/* Ahem-style text: every glyph charWidth wide, wraps at spaces; "\n" is a
   forced line break (an imported <br>); nowrap disables wrapping. */
static TRSize TRAhemMeasure(NSString *text, TRFloat cw, TRFloat lh, BOOL nowrap,
                            TRSize avail, TRMeasureMode wm)
{
  if ([text length] == 0) return TRSizeMake(0, 0);
  TRFloat limit = INFINITY;
  if (!nowrap && (wm == TRMeasureModeExactly || wm == TRMeasureModeAtMost))
    limit = avail.width;
  TRFloat maxW = 0, maxContent = 0;
  int lines = 0;
  for (NSString *para in [text componentsSeparatedByString: @"\n"])
    {
      maxContent = MAX(maxContent, [para length] * cw);
      TRFloat lineW = 0;
      lines++;
      for (NSString *w in [para componentsSeparatedByString: @" "])
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
    }
  if (wm == TRMeasureModeUndefined) maxW = maxContent;
  return TRSizeMake(maxW, lines * lh);
}

static TRNode *TRBuildNode(NSDictionary *d, NSString **err)
{
  /* A dictionary, or a declaration string where order matters
     ("margin-right: 5px; margin-inline-start: 10px"). */
  id style = d[@"style"] ?: @{};
  NSError *e = nil;
  TRStyle *st = [style isKindOfClass: [NSString class]]
    ? [TRStyle styleWithDeclarations: style error: &e]
    : [TRStyle styleWithDictionary: style error: &e];
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
          BOOL nowrap = [m[@"nowrap"] boolValue];
          n.measureBlock = ^TRSize(TRSize avail, TRMeasureMode wm, TRMeasureMode hm) {
            return TRAhemMeasure(text, cw, lh, nowrap, avail, wm);
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
      else if (m[@"text"])
        {
          /* Ahem: the font size is the glyph width and the ascent 0.8 em,
             below half the leading of the first line. */
          TRFloat cw = [m[@"charWidth"] doubleValue] ?: 10;
          TRFloat lh = [m[@"lineHeight"] doubleValue] ?: 10;
          TRFloat b = (lh - cw) / 2 + 0.8 * cw;
          n.baselineBlock = ^TRFloat(TRSize size) { return b; };
        }
    }
  for (NSDictionary *cq in d[@"conditions"])
    {
      NSError *ce = nil;
      if (![n addConditionalStyle: cq[@"style"] when: cq[@"when"] error: &ce])
        {
          *err = [ce localizedDescription];
          return nil;
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

/* Border-box origin of n in the root's coordinate space. */
static TRPoint TRAbsOrigin(TRNode *n)
{
  TRPoint p = { 0, 0 };
  for (TRNode *m = n; m != nil && [m parent] != nil; m = [m parent])
    {
      TRRect f = [m layoutFrame];
      p.x += f.x; p.y += f.y;
    }
  return p;
}

/* "anchor": [i, j, ...] names a node by child indices; "dx"/"dy" on an
   expected node are its border-box offset from that anchor (WPT offsets
   whose offsetParent is <body>, where only differences are known). */
static BOOL gHasAnchor;
static TRPoint gAnchor;

static void TRCompare(TRNode *n, NSDictionary *exp, NSString *path, TRFloat tol,
                      NSMutableArray *diffs)
{
  if (gHasAnchor && (exp[@"dx"] || exp[@"dy"]))
    {
      TRPoint a = TRAbsOrigin(n);
      TRFloat d[2] = { a.x - gAnchor.x, a.y - gAnchor.y };
      NSString *dk[2] = { @"dx", @"dy" };
      for (int i = 0; i < 2; i++)
        {
          id v = exp[dk[i]];
          if (v != nil && fabs([v doubleValue] - d[i]) > tol)
            [diffs addObject: [NSString stringWithFormat: @"%@.%@: expected %g, got %g",
                                path, dk[i], [v doubleValue], d[i]]];
        }
    }
  TRRect f = [n layoutFrame];
  /* "relativeTo": k makes x/y relative to the ancestor k levels up
     (k = 1 is the parent, the default). */
  NSInteger k = [exp[@"relativeTo"] integerValue];
  TRNode *up = [n parent];
  for (NSInteger i = 1; i < k && up != nil && [up parent] != nil; i++)
    {
      TRRect pf = [up layoutFrame];
      f.x += pf.x; f.y += pf.y;
      up = [up parent];
    }
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

/* Features a case may list in "requires" that Trellis does not implement,
   or deliberately does differently (docs/agents.md section 4). Such cases are
   skipped and counted by reason. --all runs them; --unsupported a,b replaces
   the list. */
static NSSet *gUnsupported;
static NSCountedSet *gSkipReasons;
static NSDictionary *gStale;   /* upstream-stale.json: case id -> reason */
static NSDictionary *gGaps;    /* known-gaps.json: case id -> reason */
static BOOL gRunAll;

static NSSet *TRDefaultUnsupported(void)
{
  return [NSSet setWithObjects:
    @"display-inline", @"display-inline-block",
    @"display--webkit-box",
    @"display-table",            /* display: table and its parts */
    @"overflow-axis",            /* overflow-x differs from overflow-y */
    @"flex-wrap-balance",        /* css-flexbox-2 flex-wrap: balance */
    @"subgrid",
    @"grid-lanes",               /* display: grid-lanes (masonry) */
    @"display-inline-grid",
    @"position-sticky",
    @"grid-template-shorthand",  /* grid / grid-template with area strings */
    @"abspos-ancestor-cb",       /* abspos whose containing block the format can't express (fixed, or no positioned ancestor in the case) */
    @"containing-block-height",  /* % min/max-height on a root: no way to give a CB height without fixing it */
    @"css-calc-tracks",          /* calc() in grid track lists */
    @"margin-collapse",          /* CSS 2 collapsing margins (a block is a flex column here) */
    nil];
}

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
  NSString *stale = gStale[cid];
  if (stale != nil && !gRunAll)
    {
      [gSkipReasons addObject: @"upstream-stale"];
      if (gVerbose) printf("SKIP %s: upstream-stale: %s\n", [cid UTF8String], [stale UTF8String]);
      return TRSkip;
    }
  NSString *gap = gGaps[cid];
  if (gap != nil && !gRunAll)
    {
      [gSkipReasons addObject: @"known-gap"];
      if (gVerbose) printf("SKIP %s: known-gap: %s\n", [cid UTF8String], [gap UTF8String]);
      return TRSkip;
    }
  if (c[@"skip"])
    {
      if (gVerbose) printf("SKIP %s: %s\n", [cid UTF8String], [[c[@"skip"] description] UTF8String]);
      return TRSkip;
    }
  for (NSString *req in c[@"requires"])
    if ([gUnsupported containsObject: req])
      {
        [gSkipReasons addObject: req];
        if (gVerbose) printf("SKIP %s: requires %s\n", [cid UTF8String], [req UTF8String]);
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
  gHasAnchor = NO;
  if ([c[@"anchor"] isKindOfClass: [NSArray class]])
    {
      TRNode *a = root;
      for (NSNumber *i in c[@"anchor"])
        {
          NSArray *kids = [a children];
          if ([i unsignedIntegerValue] >= [kids count]) { a = nil; break; }
          a = kids[[i unsignedIntegerValue]];
        }
      if (a == nil)
        [diffs addObject: @"anchor: no such node"];
      else
        {
          gHasAnchor = YES;
          gAnchor = TRAbsOrigin(a);
        }
    }
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
      gUnsupported = TRDefaultUnsupported();
      /* Imported cases whose expectations predate a spec change Trellis
         follows (id -> reason). Skipped by default, like an unsupported
         feature; --all runs them. Kept outside the cases so a re-import
         doesn't drop it. */
      NSData *sd = [NSData dataWithContentsOfFile: @"Tests/Conformance/upstream-stale.json"];
      id sj = sd ? [NSJSONSerialization JSONObjectWithData: sd options: 0 error: NULL] : nil;
      gStale = [sj isKindOfClass: [NSDictionary class]] ? sj[@"cases"] : nil;
      /* Cases of a supported feature that still fail (id -> reason): the
         feature's tag runs, these few don't. --all runs them too. */
      NSData *gd = [NSData dataWithContentsOfFile: @"Tests/Conformance/known-gaps.json"];
      id gj = gd ? [NSJSONSerialization JSONObjectWithData: gd options: 0 error: NULL] : nil;
      gGaps = [gj isKindOfClass: [NSDictionary class]] ? gj[@"cases"] : nil;
      gSkipReasons = [NSCountedSet set];
      for (int i = 1; i < argc; i++)
        {
          NSString *a = [NSString stringWithUTF8String: argv[i]];
          if ([a isEqualToString: @"--verbose"] || [a isEqualToString: @"-v"]) gVerbose = YES;
          else if ([a isEqualToString: @"--all"]) { gUnsupported = [NSSet set]; gRunAll = YES; }
          else if ([a isEqualToString: @"--unsupported"] && i + 1 < argc)
            {
              NSString *list = [NSString stringWithUTF8String: argv[++i]];
              gUnsupported = [NSSet setWithArray: [list length] ? [list componentsSeparatedByString: @","] : @[]];
            }
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
      if ([gSkipReasons count])
        {
          printf("  skipped, unsupported:");
          for (NSString *r in [[gSkipReasons allObjects] sortedArrayUsingSelector: @selector(compare:)])
            printf(" %s %lu", [r UTF8String], (unsigned long)[gSkipReasons countForObject: r]);
          printf("\n");
        }
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
