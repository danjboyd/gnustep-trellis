/* TRGrid.m - CSS Grid Layout (a practical subset of CSS Grid Level 1).

   Supported: grid-template-columns/rows with px, %, fr, auto, min-content,
   max-content, minmax(), repeat(N | auto-fill | auto-fit, ...);
   grid-template-areas; grid-auto-columns/rows; grid-auto-flow row|column;
   placement by line numbers (incl. negative), span N, and area names;
   auto-placement (sparse); gaps; justify/align-items/self; justify- and
   align-content distribution of tracks; rtl.

   Not (yet): named lines, subgrid, dense packing, baseline alignment,
   masonry.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRNode+Internal.h"
#import "TRGrid.h"
#include <stdlib.h>

/* ------------------------------------------------------------------ */
#pragma mark Track lists

typedef enum {
  TRBreadthFixed, TRBreadthPercent, TRBreadthFr, TRBreadthAuto,
  TRBreadthMinContent, TRBreadthMaxContent
} TRBreadthKind;

typedef struct { TRBreadthKind kind; double value; } TRBreadth;
typedef struct { TRBreadth min, max; } TRTrackSize;

typedef struct {
  TRTrackSize size;
  int repeat;            /* 0 = plain track; >0 = repeat count; -1 auto-fill; -2 auto-fit */
} TRTrackEntry;

static NSArray *TRTokenizeTracks(NSString *v)
{
  /* Split on whitespace at parenthesis depth 0. */
  NSMutableArray *out = [NSMutableArray array];
  NSMutableString *cur = [NSMutableString string];
  int depth = 0;
  for (NSUInteger i = 0; i < [v length]; i++)
    {
      unichar c = [v characterAtIndex: i];
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (depth == 0 && (c == ' ' || c == '\t' || c == '\n'))
        {
          if ([cur length]) { [out addObject: [cur copy]]; [cur setString: @""]; }
          continue;
        }
      [cur appendFormat: @"%C", c];
    }
  if ([cur length]) [out addObject: cur];
  return depth == 0 ? out : nil;
}

static BOOL TRParseBreadth(NSString *t, TRBreadth *b)
{
  t = [[t stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]] lowercaseString];
  if ([t isEqualToString: @"auto"]) { b->kind = TRBreadthAuto; b->value = 0; return YES; }
  if ([t isEqualToString: @"min-content"]) { b->kind = TRBreadthMinContent; b->value = 0; return YES; }
  if ([t isEqualToString: @"max-content"]) { b->kind = TRBreadthMaxContent; b->value = 0; return YES; }
  TRBreadthKind k = TRBreadthFixed;
  NSString *num = t;
  if ([t hasSuffix: @"fr"]) { k = TRBreadthFr; num = [t substringToIndex: [t length] - 2]; }
  else if ([t hasSuffix: @"%"]) { k = TRBreadthPercent; num = [t substringToIndex: [t length] - 1]; }
  else if ([t hasSuffix: @"px"]) num = [t substringToIndex: [t length] - 2];
  NSScanner *sc = [NSScanner scannerWithString: num];
  double d;
  if (![sc scanDouble: &d] || ![sc isAtEnd] || d < 0) return NO;
  b->kind = k;
  b->value = d;
  return YES;
}

static BOOL TRParseTrackSize(NSString *t, TRTrackSize *ts)
{
  NSString *lt = [t lowercaseString];
  if ([lt hasPrefix: @"minmax("] && [lt hasSuffix: @")"])
    {
      NSString *inner = [t substringWithRange: NSMakeRange(7, [t length] - 8)];
      NSArray *parts = [inner componentsSeparatedByString: @","];
      if ([parts count] != 2) return NO;
      if (!TRParseBreadth(parts[0], &ts->min) || !TRParseBreadth(parts[1], &ts->max)) return NO;
      if (ts->min.kind == TRBreadthFr) return NO;   /* fr is not allowed as a minimum */
      return YES;
    }
  if ([lt hasPrefix: @"fit-content("]) return NO;
  TRBreadth b;
  if (!TRParseBreadth(t, &b)) return NO;
  if (b.kind == TRBreadthFr)
    { ts->min.kind = TRBreadthAuto; ts->min.value = 0; ts->max = b; }   /* 1fr = minmax(auto, 1fr) */
  else
    { ts->min = b; ts->max = b; }
  return YES;
}

/* Parses a track list into entries; repeat() groups are flattened with
   their repeat marker on each entry and a group id. */
typedef struct { TRTrackEntry *entries; int count; int groupStart, groupLen; int groupRepeat; } TRTrackList;

static BOOL TRParseTrackList(NSString *v, TRTrackList *out, BOOL singleOnly)
{
  out->entries = NULL; out->count = 0; out->groupStart = -1; out->groupLen = 0; out->groupRepeat = 0;
  NSArray *toks = TRTokenizeTracks(v);
  if (toks == nil || [toks count] == 0) return NO;
  NSMutableData *buf = [NSMutableData data];
  int n = 0;
  for (NSString *tok in toks)
    {
      if ([tok hasPrefix: @"["]) return NO;   /* named lines: not supported */
      NSString *lt = [tok lowercaseString];
      if ([lt hasPrefix: @"repeat("] && [lt hasSuffix: @")"])
        {
          if (singleOnly) return NO;
          NSString *inner = [tok substringWithRange: NSMakeRange(7, [tok length] - 8)];
          NSRange comma = [inner rangeOfString: @","];
          if (comma.location == NSNotFound) return NO;
          NSString *countS = [[[inner substringToIndex: comma.location]
            stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]] lowercaseString];
          int rep;
          if ([countS isEqualToString: @"auto-fill"]) rep = -1;
          else if ([countS isEqualToString: @"auto-fit"]) rep = -2;
          else { rep = [countS intValue]; if (rep < 1) return NO; }
          if (rep < 0 && out->groupStart >= 0) return NO;   /* one auto repeat per list */
          NSArray *innerToks = TRTokenizeTracks([inner substringFromIndex: NSMaxRange(comma)]);
          if ([innerToks count] == 0) return NO;
          int start = n;
          for (NSString *it in innerToks)
            {
              TRTrackEntry e;
              if (!TRParseTrackSize(it, &e.size)) return NO;
              if (rep < 0 && (e.size.min.kind != TRBreadthFixed && e.size.min.kind != TRBreadthPercent)
                  && (e.size.max.kind != TRBreadthFixed && e.size.max.kind != TRBreadthPercent))
                return NO;   /* auto repeats need a definite size */
              e.repeat = rep;
              [buf appendBytes: &e length: sizeof e];
              n++;
            }
          if (rep < 0) { out->groupStart = start; out->groupLen = n - start; out->groupRepeat = rep; }
          else
            {
              /* Expand fixed repeats now. */
              NSData *group = [buf subdataWithRange: NSMakeRange(start * sizeof(TRTrackEntry), (n - start) * sizeof(TRTrackEntry))];
              for (int r = 1; r < rep; r++) { [buf appendData: group]; n += (int)([group length] / sizeof(TRTrackEntry)); }
            }
          continue;
        }
      TRTrackEntry e;
      if (!TRParseTrackSize(tok, &e.size)) return NO;
      e.repeat = 0;
      [buf appendBytes: &e length: sizeof e];
      n++;
    }
  if (singleOnly && n != 1) return NO;
  out->entries = malloc(sizeof(TRTrackEntry) * (n ? n : 1));
  memcpy(out->entries, [buf bytes], sizeof(TRTrackEntry) * n);
  out->count = n;
  return YES;
}

BOOL TRGridValidateTrackList(NSString *value, BOOL singleTracksOnly)
{
  TRTrackList l;
  BOOL ok = TRParseTrackList(value, &l, singleTracksOnly);
  free(l.entries);
  return ok;
}

/* ------------------------------------------------------------------ */
#pragma mark Lines and areas

typedef enum { TRLineAuto, TRLineNumber, TRLineSpan, TRLineName } TRLineKind;
/* The name of a TRLineName line is returned separately (strong), so it
   cannot dangle. */
typedef struct { TRLineKind kind; NSInteger n; } TRLine;

BOOL TRGridIsName(NSString *v)
{
  if ([v length] == 0) return NO;
  unichar c = [v characterAtIndex: 0];
  return ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_')
    && ![[v lowercaseString] isEqualToString: @"auto"] && ![[v lowercaseString] hasPrefix: @"span"];
}

static BOOL TRParseLine(NSString *v, TRLine *l, NSString *__strong *nameOut)
{
  v = [v stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
  l->kind = TRLineAuto; l->n = 0;
  if (nameOut) *nameOut = nil;
  if ([v length] == 0 || [[v lowercaseString] isEqualToString: @"auto"]) return YES;
  NSArray *t = [v componentsSeparatedByCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
  NSMutableArray *toks = [NSMutableArray array];
  for (NSString *x in t) if ([x length]) [toks addObject: x];
  if ([[toks[0] lowercaseString] isEqualToString: @"span"])
    {
      if ([toks count] != 2) return NO;
      NSInteger n = [toks[1] integerValue];
      if (n < 1) return NO;
      l->kind = TRLineSpan; l->n = n;
      return YES;
    }
  if ([toks count] != 1) return NO;
  NSScanner *sc = [NSScanner scannerWithString: toks[0]];
  NSInteger n;
  if ([sc scanInteger: &n] && [sc isAtEnd])
    {
      if (n == 0) return NO;
      l->kind = TRLineNumber; l->n = n;
      return YES;
    }
  if (TRGridIsName(toks[0])) { l->kind = TRLineName; if (nameOut) *nameOut = [toks[0] copy]; return YES; }
  return NO;
}

BOOL TRGridValidateLine(NSString *value)
{
  TRLine l;
  return TRParseLine(value, &l, NULL);
}

NSArray<NSArray<NSString *> *> *TRGridParseAreas(NSString *value)
{
  /* A plain character loop: NSScanner's whitespace skipping differs
     between GNUstep and Apple when a scan fails. */
  NSMutableArray *rows = [NSMutableArray array];
  NSUInteger i = 0, n = [value length];
  while (i < n)
    {
      unichar c = [value characterAtIndex: i];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { i++; continue; }
      if (c != '"') return nil;
      NSUInteger start = ++i;
      while (i < n && [value characterAtIndex: i] != '"') i++;
      if (i >= n) return nil;
      NSString *row = [value substringWithRange: NSMakeRange(start, i - start)];
      i++;
      NSMutableArray *cells = [NSMutableArray array];
      for (NSString *cell in [row componentsSeparatedByCharactersInSet: [NSCharacterSet whitespaceCharacterSet]])
        if ([cell length]) [cells addObject: ([cell hasPrefix: @"."] ? @"." : cell)];
      if ([cells count] == 0) return nil;
      if ([rows count] && [cells count] != [rows[0] count]) return nil;
      [rows addObject: cells];
    }
  if ([rows count] == 0) return nil;
  /* Every named area must be a rectangle. */
  NSMutableDictionary *bounds = [NSMutableDictionary dictionary];
  for (NSUInteger r = 0; r < [rows count]; r++)
    for (NSUInteger c = 0; c < [rows[r] count]; c++)
      {
        NSString *n = rows[r][c];
        if ([n isEqualToString: @"."]) continue;
        NSArray *b = bounds[n];
        NSUInteger r0 = b ? [b[0] unsignedIntegerValue] : r, c0 = b ? [b[1] unsignedIntegerValue] : c;
        NSUInteger r1 = b ? MAX([b[2] unsignedIntegerValue], r) : r, c1 = b ? MAX([b[3] unsignedIntegerValue], c) : c;
        bounds[n] = @[@(MIN(r0, r)), @(MIN(c0, c)), @(r1), @(c1)];
      }
  for (NSString *n in bounds)
    {
      NSArray *b = bounds[n];
      for (NSUInteger r = [b[0] unsignedIntegerValue]; r <= [b[2] unsignedIntegerValue]; r++)
        for (NSUInteger c = [b[1] unsignedIntegerValue]; c <= [b[3] unsignedIntegerValue]; c++)
          if (![rows[r][c] isEqualToString: n]) return nil;
    }
  return rows;
}

/* ------------------------------------------------------------------ */
#pragma mark Layout

typedef struct {
  TRTrackSize size;
  double base, limit;      /* limit may be INFINITY */
  BOOL collapsed;          /* empty auto-fit track */
  double pos;
} TRTrack;

typedef struct {
  __unsafe_unretained TRNode *node;
  const TRStyleStorage *s;
  NSInteger r0, r1, c0, c1;   /* [start, end) track indices */
  double margin[4];
  BOOL marginAuto[4];
  double minW, maxW;          /* min-/max-content border-box widths (+ margins) */
  double w, h;                /* final border-box size */
  double x, y;
  NSInteger docOrder;
} TRGridItem;

static inline double TRGResolve(TRValue v, double ref)
{
  switch (v.unit)
    {
      case TRUnitPoint: return v.value;
      case TRUnitPercent: return isnan(ref) ? NAN : v.value * ref / 100.0;
      default: return NAN;
    }
}

static double TRBreadthFixedValue(TRBreadth b, double avail)
{
  if (b.kind == TRBreadthFixed) return b.value;
  if (b.kind == TRBreadthPercent) return isnan(avail) ? NAN : b.value * avail / 100.0;
  return NAN;
}

/* Expands a template + auto-repeat into concrete tracks. */
static TRTrack *TRBuildTracks(NSString *tmpl, double avail, double gap, NSInteger *count,
                              NSInteger *autoFitStart, NSInteger *autoFitLen)
{
  *autoFitStart = -1; *autoFitLen = 0;
  TRTrackList l = {0};
  if (tmpl == nil || !TRParseTrackList(tmpl, &l, NO)) { *count = 0; return NULL; }
  int reps = 1;
  if (l.groupStart >= 0)
    {
      /* auto-fill/fit: as many repetitions as fit (at least 1). */
      double fixedOther = 0;
      int others = 0;
      for (int i = 0; i < l.count; i++)
        if (i < l.groupStart || i >= l.groupStart + l.groupLen)
          {
            double v = TRBreadthFixedValue(l.entries[i].size.max, avail);
            if (isnan(v)) v = TRBreadthFixedValue(l.entries[i].size.min, avail);
            fixedOther += isnan(v) ? 0 : v;
            others++;
          }
      double groupSize = 0;
      for (int i = l.groupStart; i < l.groupStart + l.groupLen; i++)
        {
          TRTrackSize ts = l.entries[i].size;
          double v = TRBreadthFixedValue(ts.max, avail);
          double mn = TRBreadthFixedValue(ts.min, avail);
          if (isnan(v) || (!isnan(mn) && mn > v)) v = mn;
          groupSize += isnan(v) ? 0 : v;
        }
      if (!isnan(avail) && groupSize > 0)
        {
          double space = avail - fixedOther - gap * others;
          double per = groupSize + gap * l.groupLen;
          reps = (int)floor((space + gap) / per);
          if (reps < 1) reps = 1;
        }
    }
  NSInteger n = l.count + (l.groupStart >= 0 ? (reps - 1) * l.groupLen : 0);
  TRTrack *t = calloc(n ? n : 1, sizeof(TRTrack));
  NSInteger k = 0;
  for (int i = 0; i < l.count; i++)
    {
      if (i == l.groupStart)
        {
          if (l.groupRepeat == -2) { *autoFitStart = k; *autoFitLen = reps * l.groupLen; }
          for (int r = 0; r < reps; r++)
            for (int j = 0; j < l.groupLen; j++)
              t[k++].size = l.entries[l.groupStart + j].size;
          i += l.groupLen - 1;
          continue;
        }
      t[k++].size = l.entries[i].size;
    }
  free(l.entries);
  *count = n;
  return t;
}

static TRTrackSize TRAutoTrackSize(NSString *autoTracks)
{
  TRTrackSize ts = { { TRBreadthAuto, 0 }, { TRBreadthAuto, 0 } };
  if (autoTracks)
    {
      TRTrackList l;
      if (TRParseTrackList(autoTracks, &l, YES)) ts = l.entries[0].size;
      free(l.entries);
    }
  return ts;
}

/* Line -> track index for one axis. Returns NO for auto. */
static BOOL TRResolveLine(TRLine l, NSString *name, NSInteger explicitCount, NSDictionary *areaLines,
                          BOOL isStart, NSInteger *out)
{
  if (l.kind == TRLineNumber)
    {
      NSInteger idx = l.n > 0 ? l.n - 1 : explicitCount + 1 + l.n;
      *out = MAX(0, idx);
      return YES;
    }
  if (l.kind == TRLineName)
    {
      NSString *key = name;
      NSString *suffix = isStart ? @"-start" : @"-end";
      if ([key hasSuffix: @"-start"] || [key hasSuffix: @"-end"])
        {
          suffix = [key hasSuffix: @"-start"] ? @"-start" : @"-end";
          key = [key substringToIndex: [key length] - [suffix length]];
        }
      NSArray *b = areaLines[key];
      if (b == nil) return NO;
      *out = [b[[suffix isEqualToString: @"-start"] ? 0 : 1] integerValue];
      return YES;
    }
  return NO;
}

static void TRSizeTracks(TRTrack *tr, NSInteger n, double avail, double gap,
                         TRGridItem *items, NSInteger nItems, BOOL columns,
                         TRAlign contentAlign)
{
  /* Initialise. */
  for (NSInteger i = 0; i < n; i++)
    {
      if (tr[i].collapsed) { tr[i].base = tr[i].limit = 0; continue; }
      double mn = TRBreadthFixedValue(tr[i].size.min, avail);
      double mx = TRBreadthFixedValue(tr[i].size.max, avail);
      tr[i].base = isnan(mn) ? 0 : mn;
      if (tr[i].size.max.kind == TRBreadthFr) tr[i].limit = INFINITY;
      else tr[i].limit = isnan(mx) ? INFINITY : mx;
      if (!isnan(mx) && tr[i].limit < tr[i].base) tr[i].limit = tr[i].base;
    }
  BOOL limitSet[n ? n : 1];
  for (NSInteger i = 0; i < n; i++)
    limitSet[i] = !isinf(tr[i].limit) || tr[i].size.max.kind == TRBreadthFr;

  /* Intrinsic contributions: single-span items first, then spanning
     items distribute any shortfall over their intrinsic tracks. */
  for (int pass = 0; pass < 2; pass++)
    for (NSInteger k = 0; k < nItems; k++)
      {
        TRGridItem *it = &items[k];
        NSInteger a = columns ? it->c0 : it->r0, b = columns ? it->c1 : it->r1;
        NSInteger span = b - a;
        if ((pass == 0) != (span == 1)) continue;
        double minC = columns ? it->minW : it->h;      /* rows: content height at the column width */
        double maxC = columns ? it->maxW : it->h;
        BOOL crossesFlex = NO;
        for (NSInteger i = a; i < b; i++) if (tr[i].size.max.kind == TRBreadthFr) crossesFlex = YES;
        if (span == 1)
          {
            TRTrack *t = &tr[a];
            if (t->collapsed) continue;
            TRBreadthKind mk = t->size.min.kind;
            if (mk == TRBreadthAuto || mk == TRBreadthMinContent)
              t->base = MAX(t->base, minC);
            else if (mk == TRBreadthMaxContent)
              t->base = MAX(t->base, maxC);
            TRBreadthKind xk = t->size.max.kind;
            if (xk == TRBreadthAuto || xk == TRBreadthMaxContent)
              { t->limit = limitSet[a] ? MAX(t->limit, maxC) : maxC; limitSet[a] = YES; }
            else if (xk == TRBreadthMinContent)
              { t->limit = limitSet[a] ? MAX(t->limit, minC) : minC; limitSet[a] = YES; }
          }
        else if (!crossesFlex)
          {
            double have = gap * (span - 1), haveL = gap * (span - 1);
            int intrinsic = 0;
            for (NSInteger i = a; i < b; i++)
              {
                have += tr[i].base;
                haveL += isinf(tr[i].limit) ? tr[i].base : tr[i].limit;
                TRBreadthKind mk = tr[i].size.min.kind;
                if (mk == TRBreadthAuto || mk == TRBreadthMinContent || mk == TRBreadthMaxContent) intrinsic++;
              }
            if (intrinsic == 0) continue;
            double extra = minC - have;
            if (extra > 0)
              for (NSInteger i = a; i < b; i++)
                {
                  TRBreadthKind mk = tr[i].size.min.kind;
                  if (mk == TRBreadthAuto || mk == TRBreadthMinContent || mk == TRBreadthMaxContent)
                    tr[i].base += extra / intrinsic;
                }
            double extraL = maxC - haveL;
            if (extraL > 0)
              for (NSInteger i = a; i < b; i++)
                {
                  TRBreadthKind xk = tr[i].size.max.kind;
                  if (xk == TRBreadthAuto || xk == TRBreadthMaxContent || xk == TRBreadthMinContent)
                    {
                      double cur = limitSet[i] ? tr[i].limit : tr[i].base;
                      tr[i].limit = cur + extraL / intrinsic;
                      limitSet[i] = YES;
                    }
                }
          }
      }
  for (NSInteger i = 0; i < n; i++)
    {
      if (!limitSet[i] && tr[i].size.max.kind != TRBreadthFr) tr[i].limit = tr[i].base;
      if (tr[i].limit < tr[i].base) tr[i].limit = tr[i].base;
    }

  double gaps = 0;
  NSInteger visible = 0;
  for (NSInteger i = 0; i < n; i++) if (!tr[i].collapsed) visible++;
  gaps = visible > 1 ? gap * (visible - 1) : 0;

  /* Maximise: grow bases toward limits with definite free space. */
  if (!isnan(avail))
    for (int guard = 0; guard < 8; guard++)
      {
        double used = gaps;
        int growable = 0;
        for (NSInteger i = 0; i < n; i++)
          {
            used += tr[i].base;
            if (tr[i].size.max.kind != TRBreadthFr && !isinf(tr[i].limit) && tr[i].limit > tr[i].base + 0.0001)
              growable++;
          }
        double free = avail - used;
        if (free <= 0.0001 || growable == 0) break;
        double share = free / growable;
        for (NSInteger i = 0; i < n; i++)
          if (tr[i].size.max.kind != TRBreadthFr && !isinf(tr[i].limit) && tr[i].limit > tr[i].base + 0.0001)
            tr[i].base = MIN(tr[i].limit, tr[i].base + share);
      }

  /* Flexible tracks. */
  BOOL anyFr = NO;
  for (NSInteger i = 0; i < n; i++) if (tr[i].size.max.kind == TRBreadthFr && !tr[i].collapsed) anyFr = YES;
  if (anyFr)
    {
      double frSize = 0;
      if (!isnan(avail))
        {
          BOOL inflexible[n ? n : 1];
          for (NSInteger i = 0; i < n; i++) inflexible[i] = (tr[i].size.max.kind != TRBreadthFr) || tr[i].collapsed;
          for (int guard = 0; guard < 16; guard++)
            {
              double leftover = avail - gaps, sumFr = 0;
              for (NSInteger i = 0; i < n; i++)
                {
                  if (inflexible[i]) leftover -= tr[i].base;
                  else sumFr += tr[i].size.max.value;
                }
              if (sumFr <= 0) break;
              frSize = MAX(0, leftover) / MAX(1.0, sumFr);
              BOOL changed = NO;
              for (NSInteger i = 0; i < n; i++)
                if (!inflexible[i] && tr[i].size.max.value * frSize < tr[i].base)
                  { inflexible[i] = YES; changed = YES; }
              if (!changed) break;
            }
        }
      else
        {
          for (NSInteger i = 0; i < n; i++)
            if (tr[i].size.max.kind == TRBreadthFr && tr[i].size.max.value > 0)
              frSize = MAX(frSize, tr[i].base / tr[i].size.max.value);
          for (NSInteger k = 0; k < nItems; k++)
            {
              TRGridItem *it = &items[k];
              NSInteger a = columns ? it->c0 : it->r0, b = columns ? it->c1 : it->r1;
              double sumFr = 0, fixed = gap * (b - a - 1);
              for (NSInteger i = a; i < b; i++)
                {
                  if (tr[i].size.max.kind == TRBreadthFr) sumFr += tr[i].size.max.value;
                  else fixed += tr[i].base;
                }
              double maxC = columns ? it->maxW : it->h;
              if (sumFr > 0) frSize = MAX(frSize, (maxC - fixed) / MAX(1.0, sumFr));
            }
        }
      for (NSInteger i = 0; i < n; i++)
        if (tr[i].size.max.kind == TRBreadthFr && !tr[i].collapsed)
          tr[i].base = MAX(tr[i].base, tr[i].size.max.value * frSize);
    }

  /* Stretch auto tracks into remaining space. */
  if (!isnan(avail) && (contentAlign == TRAlignNormal || contentAlign == TRAlignStretch))
    {
      double used = gaps;
      int autos = 0;
      for (NSInteger i = 0; i < n; i++)
        {
          used += tr[i].base;
          if (tr[i].size.max.kind == TRBreadthAuto && !tr[i].collapsed) autos++;
        }
      double free = avail - used;
      if (free > 0 && autos > 0)
        for (NSInteger i = 0; i < n; i++)
          if (tr[i].size.max.kind == TRBreadthAuto && !tr[i].collapsed) tr[i].base += free / autos;
    }
}

/* Positions tracks along an axis, honouring justify/align-content. */
static double TRPlaceTracks(TRTrack *tr, NSInteger n, double gap, double avail, TRAlign align)
{
  double total = 0;
  NSInteger visible = 0;
  for (NSInteger i = 0; i < n; i++) if (!tr[i].collapsed) { total += tr[i].base; visible++; }
  total += visible > 1 ? gap * (visible - 1) : 0;
  double free = isnan(avail) ? 0 : avail - total;
  double lead = 0, between = 0;
  switch (align)
    {
      case TRAlignEnd: case TRAlignFlexEnd: case TRAlignRight: lead = free; break;
      case TRAlignCenter: lead = free / 2; break;
      case TRAlignSpaceBetween: if (free > 0 && visible > 1) between = free / (visible - 1); break;
      case TRAlignSpaceAround: if (free > 0 && visible > 0) { between = free / visible; lead = between / 2; } break;
      case TRAlignSpaceEvenly: if (free > 0) { between = free / (visible + 1); lead = between; } break;
      default: break;
    }
  double pos = lead;
  BOOL first = YES;
  for (NSInteger i = 0; i < n; i++)
    {
      if (tr[i].collapsed) { tr[i].pos = pos; continue; }
      if (!first) pos += gap + between;
      tr[i].pos = pos;
      pos += tr[i].base;
      first = NO;
    }
  return total;
}

static double TRSpanSize(TRTrack *tr, NSInteger a, NSInteger b)
{
  if (b <= a) return 0;
  NSInteger last = b - 1;
  return tr[last].pos + tr[last].base - tr[a].pos;
}

static int TRCompareItemOrder(const void *x, const void *y)
{
  const TRGridItem *a = x, *b = y;
  if (a->s->order != b->s->order) return a->s->order < b->s->order ? -1 : 1;
  return a->docOrder < b->docOrder ? -1 : (a->docOrder > b->docOrder ? 1 : 0);
}

TRSize TRLayoutGrid(TRNode *node, const TRStyleStorage *s, TRFloat pad[4], TRFloat border[4],
                    TRFloat aw, TRFloat ah, TRMeasureMode wm, TRMeasureMode hm,
                    TRFloat ow, TRFloat oh, BOOL perform, TRDirection dir);

TRSize TRLayoutGrid(TRNode *node, const TRStyleStorage *s, TRFloat pad[4], TRFloat border[4],
                    TRFloat aw, TRFloat ah, TRMeasureMode wm, TRMeasureMode hm,
                    TRFloat ow, TRFloat oh, BOOL perform, TRDirection dir)
{
  TRStyle *st = node->_style;
  const double pbW = pad[TREdgeLeft] + pad[TREdgeRight] + border[TREdgeLeft] + border[TREdgeRight];
  const double pbH = pad[TREdgeTop] + pad[TREdgeBottom] + border[TREdgeTop] + border[TREdgeBottom];
  const double innerW = wm == TRMeasureModeUndefined ? NAN : MAX(0, aw - pbW);
  const double innerH = hm == TRMeasureModeExactly ? MAX(0, ah - pbH) : NAN;
  const double colGap = MAX(0, isnan(TRGResolve(s->columnGap, innerW)) ? 0 : TRGResolve(s->columnGap, innerW));
  const double rowGap = MAX(0, isnan(TRGResolve(s->rowGap, innerH)) ? 0 : TRGResolve(s->rowGap, innerH));
  const BOOL rtl = (dir == TRDirectionRTL);

  /* ---- Explicit grid ---- */
  NSInteger nCols = 0, nRows = 0, fitStartC, fitLenC, fitStartR, fitLenR;
  TRTrack *colsT = TRBuildTracks(st->_gridTemplateColumns, innerW, colGap, &nCols, &fitStartC, &fitLenC);
  TRTrack *rowsT = TRBuildTracks(st->_gridTemplateRows, innerH, rowGap, &nRows, &fitStartR, &fitLenR);
  NSArray *areas = st->_gridTemplateAreas;
  NSInteger areaRows = [areas count], areaCols = areaRows ? [areas[0] count] : 0;
  NSInteger explicitCols = MAX(nCols, areaCols), explicitRows = MAX(nRows, areaRows);
  NSMutableDictionary *colLines = [NSMutableDictionary dictionary], *rowLines = [NSMutableDictionary dictionary];
  for (NSInteger r = 0; r < areaRows; r++)
    for (NSInteger c = 0; c < areaCols; c++)
      {
        NSString *nm = areas[r][c];
        if ([nm isEqualToString: @"."]) continue;
        NSArray *cl = colLines[nm], *rl = rowLines[nm];
        colLines[nm] = @[@(cl ? MIN([cl[0] integerValue], c) : c), @(cl ? MAX([cl[1] integerValue], c + 1) : c + 1)];
        rowLines[nm] = @[@(rl ? MIN([rl[0] integerValue], r) : r), @(rl ? MAX([rl[1] integerValue], r + 1) : r + 1)];
      }

  /* ---- Items and placement ---- */
  NSArray *children = node->_children;
  NSUInteger nc = [children count];
  TRGridItem *items = calloc(nc ? nc : 1, sizeof(TRGridItem));
  NSInteger n = 0;
  for (NSUInteger i = 0; i < nc; i++)
    {
      TRNode *c = children[i];
      const TRStyleStorage *cs = &c->_style->_s;
      if (cs->display == TRDisplayNone) continue;
      if (cs->position == TRPositionAbsolute) continue;
      items[n].node = c; items[n].s = cs; items[n].docOrder = (NSInteger)i;
      n++;
    }
  if (n > 1) qsort(items, (size_t)n, sizeof(TRGridItem), TRCompareItemOrder);

  BOOL colFlow = s->gridAutoFlowColumn;
  NSInteger gridCols = MAX(explicitCols, 1), gridRows = MAX(explicitRows, 0);
  /* Occupancy, grown on demand: major axis = rows for row flow. */
  /* __block: the minor axis can widen below, and the blocks must see it. */
  __block NSMutableData *occ = [NSMutableData data];
  __block NSInteger occMinor = colFlow ? MAX(explicitRows, 1) : gridCols;
  #define OCC(major, minor) (((char *)[occ mutableBytes])[(major) * occMinor + (minor)])

  BOOL (^fits)(NSInteger, NSInteger, NSInteger, NSInteger) = ^BOOL(NSInteger maj, NSInteger min, NSInteger majSpan, NSInteger minSpan) {
    if (min + minSpan > occMinor) return NO;
    NSInteger rowsNeeded = maj + majSpan;
    if ((NSInteger)[occ length] < rowsNeeded * occMinor) [occ setLength: rowsNeeded * occMinor];
    for (NSInteger a = maj; a < maj + majSpan; a++)
      for (NSInteger b = min; b < min + minSpan; b++)
        if (OCC(a, b)) return NO;
    return YES;
  };
  void (^mark)(NSInteger, NSInteger, NSInteger, NSInteger) = ^(NSInteger maj, NSInteger min, NSInteger majSpan, NSInteger minSpan) {
    NSInteger rowsNeeded = maj + majSpan;
    if ((NSInteger)[occ length] < rowsNeeded * occMinor) [occ setLength: rowsNeeded * occMinor];
    for (NSInteger a = maj; a < maj + majSpan; a++)
      for (NSInteger b = min; b < min + minSpan; b++)
        OCC(a, b) = 1;
  };

  /* Resolve definite lines first; items spanning past the explicit
     minor axis widen it before any auto-placement. */
  typedef struct { BOOL rDef, cDef; NSInteger rs, rspan, cs, cspan; } TRPlace;
  TRPlace *pl = calloc(n ? n : 1, sizeof(TRPlace));
  for (NSInteger k = 0; k < n; k++)
    {
      TRStyle *cst = items[k].node->_style;
      TRLine a, b;
      for (int axis = 0; axis < 2; axis++)
        {
          NSString *sv = axis == 0 ? cst->_gridRowStart : cst->_gridColumnStart;
          NSString *ev = axis == 0 ? cst->_gridRowEnd : cst->_gridColumnEnd;
          NSString *aName = nil, *bName = nil;
          TRParseLine(sv, &a, &aName);
          TRParseLine(ev, &b, &bName);
          NSInteger expl = axis == 0 ? explicitRows : explicitCols;
          NSDictionary *names = axis == 0 ? rowLines : colLines;
          NSInteger si = 0, ei = 0;
          BOOL sDef = TRResolveLine(a, aName, expl, names, YES, &si);
          BOOL eDef = TRResolveLine(b, bName, expl, names, NO, &ei);
          NSInteger span = 1;
          BOOL def = NO;
          NSInteger start = 0;
          if (sDef && eDef) { if (ei < si) { NSInteger t = si; si = ei; ei = t; } if (ei == si) ei = si + 1; start = si; span = ei - si; def = YES; }
          else if (sDef) { start = si; span = b.kind == TRLineSpan ? b.n : 1; def = YES; }
          else if (eDef) { span = a.kind == TRLineSpan ? a.n : 1; start = MAX(0, ei - span); def = YES; }
          else span = a.kind == TRLineSpan ? a.n : (b.kind == TRLineSpan ? b.n : 1);
          if (axis == 0) { pl[k].rDef = def; pl[k].rs = start; pl[k].rspan = span; }
          else { pl[k].cDef = def; pl[k].cs = start; pl[k].cspan = span; }
        }
      NSInteger minorEnd = colFlow ? (pl[k].rDef ? pl[k].rs + pl[k].rspan : pl[k].rspan)
                                   : (pl[k].cDef ? pl[k].cs + pl[k].cspan : pl[k].cspan);
      if (minorEnd > occMinor)
        {
          /* Widen the minor axis: re-layout occupancy rows. */
          NSInteger rowsHave = [occ length] / (occMinor ? occMinor : 1);
          NSMutableData *n2 = [NSMutableData dataWithLength: rowsHave * minorEnd];
          for (NSInteger r = 0; r < rowsHave; r++)
            memcpy((char *)[n2 mutableBytes] + r * minorEnd, (char *)[occ bytes] + r * occMinor, occMinor);
          occ = n2;
          occMinor = minorEnd;
        }
    }
  /* 1. fully definite items */
  for (NSInteger k = 0; k < n; k++)
    if (pl[k].rDef && pl[k].cDef)
      {
        NSInteger maj = colFlow ? pl[k].cs : pl[k].rs, min = colFlow ? pl[k].rs : pl[k].cs;
        NSInteger ms = colFlow ? pl[k].cspan : pl[k].rspan, ns = colFlow ? pl[k].rspan : pl[k].cspan;
        mark(maj, min, ms, ns);
      }
  /* 2. the rest, in order, with a sparse cursor */
  NSInteger curMaj = 0, curMin = 0;
  for (NSInteger k = 0; k < n; k++)
    {
      if (pl[k].rDef && pl[k].cDef) continue;
      BOOL majDef = colFlow ? pl[k].cDef : pl[k].rDef;
      BOOL minDef = colFlow ? pl[k].rDef : pl[k].cDef;
      NSInteger majStart = colFlow ? pl[k].cs : pl[k].rs, minStart = colFlow ? pl[k].rs : pl[k].cs;
      NSInteger majSpan = colFlow ? pl[k].cspan : pl[k].rspan, minSpan = colFlow ? pl[k].rspan : pl[k].cspan;
      NSInteger maj, min;
      if (majDef)
        {
          maj = majStart;
          for (min = 0; !fits(maj, min, majSpan, minSpan); min++)
            if (min + minSpan > occMinor) { min = 0; break; }
        }
      else if (minDef)
        {
          min = minStart;
          maj = curMaj;
          if (min < curMin) maj++;
          while (!fits(maj, min, majSpan, minSpan)) maj++;
          curMaj = maj; curMin = min + minSpan;
        }
      else
        {
          maj = curMaj; min = curMin;
          for (;;)
            {
              if (min + minSpan > occMinor) { maj++; min = 0; continue; }
              if (fits(maj, min, majSpan, minSpan)) break;
              min++;
            }
          curMaj = maj; curMin = min + minSpan;
        }
      mark(maj, min, majSpan, minSpan);
      if (colFlow) { pl[k].cs = maj; pl[k].rs = min; } else { pl[k].rs = maj; pl[k].cs = min; }
    }
  for (NSInteger k = 0; k < n; k++)
    {
      items[k].r0 = pl[k].rs; items[k].r1 = pl[k].rs + pl[k].rspan;
      items[k].c0 = pl[k].cs; items[k].c1 = pl[k].cs + pl[k].cspan;
      gridRows = MAX(gridRows, items[k].r1);
      gridCols = MAX(gridCols, items[k].c1);
    }
  free(pl);
  #undef OCC

  /* ---- Implicit tracks ---- */
  TRTrackSize autoCol = TRAutoTrackSize(st->_gridAutoColumns), autoRow = TRAutoTrackSize(st->_gridAutoRows);
  if (gridCols > nCols)
    {
      colsT = realloc(colsT, sizeof(TRTrack) * gridCols);
      for (NSInteger i = nCols; i < gridCols; i++) { memset(&colsT[i], 0, sizeof(TRTrack)); colsT[i].size = autoCol; }
      nCols = gridCols;
    }
  if (gridRows > nRows)
    {
      rowsT = realloc(rowsT, sizeof(TRTrack) * (gridRows ? gridRows : 1));
      for (NSInteger i = nRows; i < gridRows; i++) { memset(&rowsT[i], 0, sizeof(TRTrack)); rowsT[i].size = autoRow; }
      nRows = gridRows;
    }
  /* auto-fit: empty repeated tracks collapse. */
  for (int axis = 0; axis < 2; axis++)
    {
      NSInteger fs = axis ? fitStartR : fitStartC, fl = axis ? fitLenR : fitLenC;
      TRTrack *t = axis ? rowsT : colsT;
      for (NSInteger i = fs; fs >= 0 && i < fs + fl; i++)
        {
          BOOL used = NO;
          for (NSInteger k = 0; k < n && !used; k++)
            used = axis ? (items[k].r0 <= i && i < items[k].r1) : (items[k].c0 <= i && i < items[k].c1);
          t[i].collapsed = !used;
        }
    }

  /* ---- Item resolved margins and content widths ---- */
  for (NSInteger k = 0; k < n; k++)
    {
      TRGridItem *it = &items[k];
      const TRStyleStorage *cs = it->s;
      for (int e = 0; e < 4; e++)
        {
          it->marginAuto[e] = cs->margin[e].unit == TRUnitAuto;
          double m = TRGResolve(cs->margin[e], innerW);
          it->margin[e] = isnan(m) ? 0 : m;
        }
      double mh = it->margin[TREdgeLeft] + it->margin[TREdgeRight];
      double sw = TRGResolve(cs->width, NAN);
      if (!isnan(sw))
        it->minW = it->maxW = sw + mh;
      else
        {
          TRSize mn = TRLayoutNode(it->node, 0, NAN, TRMeasureModeAtMost, TRMeasureModeUndefined, NAN, NAN, NO, dir);
          TRSize mx = TRLayoutNode(it->node, NAN, NAN, TRMeasureModeUndefined, TRMeasureModeUndefined, NAN, NAN, NO, dir);
          it->minW = mn.width + mh;
          it->maxW = MAX(mx.width, mn.width) + mh;
        }
    }

  /* ---- Columns ---- */
  TRSizeTracks(colsT, nCols, innerW, colGap, items, n, YES, s->justifyContent);
  double colsTotal = TRPlaceTracks(colsT, nCols, colGap, innerW, s->justifyContent);

  /* ---- Row contributions: content height at the resolved column width ---- */
  for (NSInteger k = 0; k < n; k++)
    {
      TRGridItem *it = &items[k];
      const TRStyleStorage *cs = it->s;
      double areaW = TRSpanSize(colsT, it->c0, it->c1);
      double mh = it->margin[TREdgeLeft] + it->margin[TREdgeRight];
      double mv = it->margin[TREdgeTop] + it->margin[TREdgeBottom];
      double sh = TRGResolve(cs->height, NAN);
      if (!isnan(sh)) { it->h = sh + mv; continue; }
      TRAlign js = cs->justifySelf == TRAlignAuto ? s->justifyItems : cs->justifySelf;
      double sw = TRGResolve(cs->width, areaW);
      BOOL stretchW = isnan(sw) && (js == TRAlignNormal || js == TRAlignStretch)
                      && !it->marginAuto[TREdgeLeft] && !it->marginAuto[TREdgeRight];
      double w = !isnan(sw) ? sw : MAX(0, areaW - mh);
      TRSize sz = TRLayoutNode(it->node, w, NAN, (stretchW || !isnan(sw)) ? TRMeasureModeExactly : TRMeasureModeAtMost,
                               TRMeasureModeUndefined, areaW, NAN, NO, dir);
      it->h = sz.height + mv;
    }
  TRSizeTracks(rowsT, nRows, innerH, rowGap, items, n, NO, s->alignContent);
  double rowsTotal = TRPlaceTracks(rowsT, nRows, rowGap, innerH, s->alignContent);

  /* ---- Container size ---- */
  double W = wm == TRMeasureModeExactly ? aw : colsTotal + pbW;
  if (wm == TRMeasureModeAtMost) W = MIN(aw, W);
  double H = hm == TRMeasureModeExactly ? ah : rowsTotal + pbH;
  if (hm == TRMeasureModeAtMost) H = MIN(ah, H);
  W = MAX(W, pbW);
  H = MAX(H, pbH);

  if (perform)
    {
      double innerFinalW = W - pbW;
      double maxX = 0, maxY = 0;
      for (NSInteger k = 0; k < n; k++)
        {
          TRGridItem *it = &items[k];
          const TRStyleStorage *cs = it->s;
          double ax = colsT[it->c0].pos, ay = rowsT[it->r0].pos;
          double areaW = TRSpanSize(colsT, it->c0, it->c1), areaH = TRSpanSize(rowsT, it->r0, it->r1);
          double mh = it->margin[TREdgeLeft] + it->margin[TREdgeRight];
          double mv = it->margin[TREdgeTop] + it->margin[TREdgeBottom];
          TRAlign js = cs->justifySelf == TRAlignAuto ? s->justifyItems : cs->justifySelf;
          TRAlign as = cs->alignSelf == TRAlignAuto ? s->alignItems : cs->alignSelf;
          double sw = TRGResolve(cs->width, areaW), sh = TRGResolve(cs->height, areaH);
          double ar = cs->aspectRatio;
          if (isnan(sw) && !isnan(sh) && !isnan(ar)) sw = sh * ar;
          if (isnan(sh) && !isnan(sw) && !isnan(ar)) sh = sw / ar;
          BOOL autoL = it->marginAuto[TREdgeLeft], autoR = it->marginAuto[TREdgeRight];
          BOOL autoT = it->marginAuto[TREdgeTop], autoB = it->marginAuto[TREdgeBottom];
          double w, h;
          if (!isnan(sw)) w = sw;
          else if ((js == TRAlignNormal || js == TRAlignStretch) && !autoL && !autoR) w = MAX(0, areaW - mh);
          else
            {
              TRSize sz = TRLayoutNode(it->node, MAX(0, areaW - mh), NAN, TRMeasureModeAtMost, TRMeasureModeUndefined,
                                       areaW, areaH, NO, dir);
              w = sz.width;
            }
          double minw = TRGResolve(cs->minWidth, areaW), maxw = TRGResolve(cs->maxWidth, areaW);
          if (!isnan(maxw)) w = MIN(w, maxw);
          if (!isnan(minw)) w = MAX(w, minw);
          if (!isnan(sh)) h = sh;
          else if ((as == TRAlignNormal || as == TRAlignStretch) && !autoT && !autoB && isnan(ar)) h = MAX(0, areaH - mv);
          else
            {
              TRSize sz = TRLayoutNode(it->node, w, NAN, TRMeasureModeExactly, TRMeasureModeUndefined, areaW, areaH, NO, dir);
              h = sz.height;
            }
          double minh = TRGResolve(cs->minHeight, areaH), maxh = TRGResolve(cs->maxHeight, areaH);
          if (!isnan(maxh)) h = MIN(h, maxh);
          if (!isnan(minh)) h = MAX(h, minh);

          double freeW = areaW - mh - w, freeH = areaH - mv - h;
          double offX = it->margin[TREdgeLeft], offY = it->margin[TREdgeTop];
          if (autoL && autoR) offX += MAX(0, freeW) / 2;
          else if (autoL) offX += MAX(0, freeW);
          else if (!autoR)
            {
              if (js == TRAlignCenter) offX += freeW / 2;
              else if (js == TRAlignEnd || js == TRAlignFlexEnd || js == TRAlignRight) offX += freeW;
            }
          if (autoT && autoB) offY += MAX(0, freeH) / 2;
          else if (autoT) offY += MAX(0, freeH);
          else if (!autoB)
            {
              if (as == TRAlignCenter) offY += freeH / 2;
              else if (as == TRAlignEnd || as == TRAlignFlexEnd) offY += freeH;
            }
          double x = ax + offX, y = ay + offY;
          if (rtl) x = innerFinalW - x - w;
          x += pad[TREdgeLeft] + border[TREdgeLeft];
          y += pad[TREdgeTop] + border[TREdgeTop];
          TRLayoutNode(it->node, w, h, TRMeasureModeExactly, TRMeasureModeExactly, areaW, areaH, YES, dir);
          TRNode *c = it->node;
          c->_rawFrame = TRRectMake(x, y, w, h);
          c->_lineIndex = it->r0 == 0 ? 0 : 1;
          for (int e = 0; e < 4; e++) c->_lmargin[e] = it->margin[e];
          maxX = MAX(maxX, x + w + it->margin[TREdgeRight]);
          maxY = MAX(maxY, y + h + it->margin[TREdgeBottom]);
        }
      /* Absolutely positioned children: against the padding box. */
      double cbW = W - border[TREdgeLeft] - border[TREdgeRight];
      double cbH = H - border[TREdgeTop] - border[TREdgeBottom];
      for (NSUInteger i = 0; i < nc; i++)
        {
          TRNode *c = children[i];
          const TRStyleStorage *cs = &c->_style->_s;
          if (cs->display == TRDisplayNone || cs->position != TRPositionAbsolute) continue;
          double L = TRGResolve(cs->inset[TREdgeLeft], cbW), R = TRGResolve(cs->inset[TREdgeRight], cbW);
          double T = TRGResolve(cs->inset[TREdgeTop], cbH), B = TRGResolve(cs->inset[TREdgeBottom], cbH);
          double w = TRGResolve(cs->width, cbW), h = TRGResolve(cs->height, cbH);
          if (isnan(w) && !isnan(L) && !isnan(R)) w = MAX(0, cbW - L - R);
          if (isnan(h) && !isnan(T) && !isnan(B)) h = MAX(0, cbH - T - B);
          if (isnan(w) || isnan(h))
            {
              TRSize sz = TRLayoutNode(c, isnan(w) ? cbW : w, isnan(h) ? NAN : h,
                                       isnan(w) ? TRMeasureModeAtMost : TRMeasureModeExactly,
                                       isnan(h) ? TRMeasureModeUndefined : TRMeasureModeExactly, cbW, cbH, NO, dir);
              if (isnan(w)) w = sz.width;
              if (isnan(h)) h = sz.height;
            }
          TRLayoutNode(c, w, h, TRMeasureModeExactly, TRMeasureModeExactly, cbW, cbH, YES, dir);
          double x = !isnan(L) ? border[TREdgeLeft] + L : (!isnan(R) ? W - border[TREdgeRight] - R - w : pad[TREdgeLeft] + border[TREdgeLeft]);
          double y = !isnan(T) ? border[TREdgeTop] + T : (!isnan(B) ? H - border[TREdgeBottom] - B - h : pad[TREdgeTop] + border[TREdgeTop]);
          c->_rawFrame = TRRectMake(x, y, w, h);
          c->_lineIndex = -1;
        }
      node->_contentSize = TRSizeMake(MAX(W, maxX + pad[TREdgeRight] + border[TREdgeRight]),
                                      MAX(H, maxY + pad[TREdgeBottom] + border[TREdgeBottom]));
    }
  free(items);
  free(colsT);
  free(rowsT);
  return TRSizeMake(W, H);
}
