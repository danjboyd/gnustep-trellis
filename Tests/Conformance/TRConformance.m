/* Trellis conformance runner: case loading, comparison and reporting.
 *
 * Copyright (C) 2026 Trellis contributors.  LGPL-2.1-or-later.
 *
 * Usage: trellis-conformance [options] [cases-dir]
 *   --suite NAME      only run cases whose id starts with NAME/
 *   --filter TEXT     only run cases whose id contains TEXT
 *   --results FILE    write per-case results as JSON (for failure ranking)
 *   --summary FILE    write the per-suite summary as JSON
 *   --verbose         print every failure with its first mismatch
 *   --min-pass PCT    exit 1 if the overall pass rate is below PCT
 *
 * Prints "PASS n/m (x%)" per suite and overall; skipped cases (unsupported
 * features, "skip") are excluded from m and listed separately.
 */
#import "TRConformance.h"
#include <math.h>

TRConfSize TRConfMeasure(NSDictionary *measure, double width, int widthMode,
                         double height, int heightMode)
{
  TRConfSize r = {0, 0};
  if (measure[@"text"] == nil) {
    r.width = [measure[@"width"] doubleValue];
    r.height = [measure[@"height"] doubleValue];
  } else {
    NSString *text = measure[@"text"];
    double cw = measure[@"charWidth"] ? [measure[@"charWidth"] doubleValue] : 10;
    double lh = measure[@"lineHeight"] ? [measure[@"lineHeight"] doubleValue] : cw;
    NSArray *words = [text componentsSeparatedByString:@" "];
    double maxContent = [text length] * cw;
    double limit = INFINITY;
    if ((widthMode == 1 || widthMode == 2) && ![measure[@"nowrap"] boolValue])
      limit = width;
    /* Greedy wrap. */
    double line = 0, longest = 0;
    int lines = [text length] ? 1 : 0;
    for (NSString *w in words) {
      double ww = [w length] * cw;
      if (line == 0) {
        line = ww;
      } else if (line + cw + ww <= limit + 1e-6) {
        line += cw + ww;
      } else {
        longest = MAX(longest, line);
        line = ww;
        lines++;
      }
    }
    longest = MAX(longest, line);
    if (widthMode == 1)
      r.width = width;
    else if (widthMode == 2)
      r.width = MIN(width, MIN(longest, maxContent));
    else
      r.width = maxContent;
    r.height = lines * lh;
  }
  if (widthMode == 1) r.width = width;
  else if (widthMode == 2) r.width = MIN(r.width, width);
  if (heightMode == 1) r.height = height;
  else if (heightMode == 2) r.height = MIN(r.height, height);
  return r;
}

static void collectCases(NSString *dir, NSMutableArray *out)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *en = [fm enumeratorAtPath:dir];
  NSString *rel;
  NSMutableArray *paths = [NSMutableArray array];
  while ((rel = [en nextObject]) != nil) {
    if ([[rel pathExtension] isEqualToString:@"json"])
      [paths addObject:[dir stringByAppendingPathComponent:rel]];
  }
  [paths sortUsingSelector:@selector(compare:)];
  for (NSString *p in paths) {
    NSData *d = [NSData dataWithContentsOfFile:p];
    NSError *err = nil;
    id obj = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:&err] : nil;
    if (![obj isKindOfClass:[NSDictionary class]]) {
      fprintf(stderr, "warning: can't parse %s\n", [p UTF8String]);
      continue;
    }
    if ([obj[@"cases"] isKindOfClass:[NSArray class]])
      [out addObjectsFromArray:obj[@"cases"]];
    else
      [out addObject:obj];
  }
}

/* Compare expected against actual.  `chain` holds the actual frames from
 * the root down to the current node, for "relativeTo". */
static void compare(NSDictionary *exp, NSDictionary *act, NSMutableArray *chain,
                    NSString *path, double tol, NSMutableArray *mismatches)
{
  if (act == nil) {
    [mismatches addObject:[NSString stringWithFormat:@"%@: missing node", path]];
    return;
  }
  [chain addObject:act];
  int rel = exp[@"relativeTo"] ? [exp[@"relativeTo"] intValue] : 1;
  for (NSString *k in @[@"x", @"y", @"width", @"height"]) {
    id e = exp[k];
    if (![e isKindOfClass:[NSNumber class]])
      continue;
    double ev = [e doubleValue];
    double av = [act[k] doubleValue];
    if (rel > 1 && ([k isEqualToString:@"x"] || [k isEqualToString:@"y"])) {
      NSInteger n = [chain count];
      for (int i = 1; i < rel && n - 1 - i >= 0; i++)
        av += [chain[n - 1 - i][k] doubleValue];
    }
    if (isnan(av) || fabs(av - ev) > tol)
      [mismatches addObject:[NSString stringWithFormat:@"%@.%@ expected %g got %g",
                             path, k, ev, av]];
  }
  NSArray *ec = exp[@"children"], *ac = act[@"children"];
  for (NSUInteger i = 0; i < [ec count]; i++) {
    NSString *p = [NSString stringWithFormat:@"%@/%lu", path, (unsigned long)i];
    compare(ec[i], i < [ac count] ? ac[i] : nil, chain, p, tol, mismatches);
  }
  [chain removeLastObject];
}

static NSString *suiteOf(NSString *caseId)
{
  NSRange r = [caseId rangeOfString:@"/"];
  return r.location == NSNotFound ? caseId : [caseId substringToIndex:r.location];
}

static void writeJSON(id obj, NSString *path)
{
  NSData *d = [NSJSONSerialization dataWithJSONObject:obj
                                              options:NSJSONWritingPrettyPrinted
                                                error:NULL];
  [d writeToFile:path atomically:YES];
}

int TRConfRunMain(id<TRConfEngine> engine, int argc, const char **argv)
{
  @autoreleasepool {
    NSString *dir = nil, *suite = nil, *filter = nil, *resultsPath = nil,
             *summaryPath = nil;
    BOOL verbose = NO;
    double minPass = -1;
    for (int i = 1; i < argc; i++) {
      NSString *a = [NSString stringWithUTF8String:argv[i]];
      NSString *next = i + 1 < argc ? [NSString stringWithUTF8String:argv[i + 1]] : nil;
      if ([a isEqualToString:@"--suite"]) { suite = next; i++; }
      else if ([a isEqualToString:@"--filter"]) { filter = next; i++; }
      else if ([a isEqualToString:@"--results"]) { resultsPath = next; i++; }
      else if ([a isEqualToString:@"--summary"]) { summaryPath = next; i++; }
      else if ([a isEqualToString:@"--min-pass"]) { minPass = [next doubleValue]; i++; }
      else if ([a isEqualToString:@"--verbose"] || [a isEqualToString:@"-v"]) verbose = YES;
      else dir = a;
    }
    if (dir == nil) {
      NSString *exe = [NSString stringWithUTF8String:argv[0]];
      dir = [[exe stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"cases"];
      if (![[NSFileManager defaultManager] fileExistsAtPath:dir])
        dir = @"Tests/Conformance/cases";
    }
    NSMutableArray *cases = [NSMutableArray array];
    collectCases(dir, cases);
    if ([cases count] == 0) {
      fprintf(stderr, "no cases found under %s\n", [dir UTF8String]);
      return 2;
    }

    NSSet *unsupported = [engine unsupportedFeatures];
    NSMutableDictionary *stats = [NSMutableDictionary dictionary];   // suite -> counts
    NSMutableArray *results = [NSMutableArray array];
    NSMutableDictionary *skipReasons = [NSMutableDictionary dictionary];

    for (NSDictionary *c in cases) {
      NSString *cid = c[@"id"] ?: @"?";
      if (suite && ![cid hasPrefix:[suite stringByAppendingString:@"/"]]) continue;
      if (filter && [cid rangeOfString:filter].location == NSNotFound) continue;
      NSString *s = suiteOf(cid);
      NSMutableDictionary *st = stats[s];
      if (!st) {
        st = [@{@"pass": @0, @"fail": @0, @"skip": @0} mutableCopy];
        stats[s] = st;
      }
      NSString *skip = nil;
      if ([c[@"skip"] isKindOfClass:[NSString class]]) {
        skip = [@"skip: " stringByAppendingString:c[@"skip"]];
      } else {
        for (NSString *req in c[@"requires"])
          if ([unsupported containsObject:req]) { skip = [@"requires " stringByAppendingString:req]; break; }
      }
      if (skip) {
        st[@"skip"] = @([st[@"skip"] intValue] + 1);
        skipReasons[skip] = @([skipReasons[skip] intValue] + 1);
        [results addObject:@{@"id": cid, @"status": @"skip", @"reason": skip}];
        continue;
      }
      NSString *err = nil;
      NSDictionary *act = nil;
      @try {
        act = [engine layoutCase:c error:&err];
      } @catch (NSException *e) {
        err = [NSString stringWithFormat:@"exception %@: %@", [e name], [e reason]];
      }
      NSMutableArray *mm = [NSMutableArray array];
      if (act == nil) {
        [mm addObject:err ?: @"engine returned no layout"];
      } else {
        double tol = c[@"tolerance"] ? [c[@"tolerance"] doubleValue] : 0.5;
        NSMutableDictionary *exp = [c[@"expected"] mutableCopy];
        compare(exp, act, [NSMutableArray array], @"root", tol, mm);
      }
      BOOL ok = [mm count] == 0;
      st[ok ? @"pass" : @"fail"] = @([st[ok ? @"pass" : @"fail"] intValue] + 1);
      NSMutableDictionary *r = [@{@"id": cid, @"status": ok ? @"pass" : @"fail"} mutableCopy];
      if (!ok) {
        r[@"mismatches"] = mm;
        if (c[@"requires"]) r[@"requires"] = c[@"requires"];
        if (verbose)
          printf("FAIL %s: %s%s\n", [cid UTF8String], [mm[0] UTF8String],
                 [mm count] > 1 ? [[NSString stringWithFormat:@" (+%lu more)",
                                    (unsigned long)[mm count] - 1] UTF8String] : "");
      }
      [results addObject:r];
    }

    int tp = 0, tf = 0, ts = 0;
    NSMutableDictionary *summary = [NSMutableDictionary dictionary];
    printf("Trellis conformance (%s engine, %s)\n", [[engine engineName] UTF8String],
#if defined(__APPLE__)
           "macOS"
#else
           "GNUstep"
#endif
           );
    for (NSString *s in [[stats allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
      int p = [stats[s][@"pass"] intValue], f = [stats[s][@"fail"] intValue],
          k = [stats[s][@"skip"] intValue];
      tp += p; tf += f; ts += k;
      double pct = p + f ? 100.0 * p / (p + f) : 0;
      printf("  %-8s PASS %d/%d (%.1f%%)  skipped %d\n", [s UTF8String], p, p + f, pct, k);
      summary[s] = @{@"pass": @(p), @"total": @(p + f), @"skipped": @(k)};
    }
    double pct = tp + tf ? 100.0 * tp / (tp + tf) : 0;
    printf("PASS %d/%d (%.1f%%)  skipped %d\n", tp, tp + tf, pct, ts);
    if ([skipReasons count]) {
      NSArray *keys = [skipReasons keysSortedByValueUsingComparator:^NSComparisonResult(id a, id b) {
        return [b compare:a];
      }];
      printf("Skipped by reason:");
      for (NSString *k in keys)
        printf(" %s=%d", [k UTF8String], [skipReasons[k] intValue]);
      printf("\n");
    }
    summary[@"all"] = @{@"pass": @(tp), @"total": @(tp + tf), @"skipped": @(ts)};
    summary[@"engine"] = [engine engineName];
    if (resultsPath) writeJSON(results, resultsPath);
    if (summaryPath) writeJSON(summary, summaryPath);
    if (minPass >= 0 && pct < minPass) return 1;
    return 0;
  }
}
