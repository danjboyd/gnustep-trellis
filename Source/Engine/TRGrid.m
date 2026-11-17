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
  TRBreadthMinContent, TRBreadthMaxContent,
  /* fit-content(N) as a maximum: max-content, capped at N (px or %). */
  TRBreadthFitContent, TRBreadthFitContentPercent
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
  if ([lt hasPrefix: @"fit-content("] && [lt hasSuffix: @")"])
    {
      /* fit-content(N) = minmax(auto, max-content), the limit capped at N. */
      TRBreadth n;
      if (!TRParseBreadth([t substringWithRange: NSMakeRange(12, [t length] - 13)], &n)) return NO;
      if (n.kind != TRBreadthFixed && n.kind != TRBreadthPercent) return NO;
      ts->min.kind = TRBreadthAuto; ts->min.value = 0;
      ts->max.kind = n.kind == TRBreadthFixed ? TRBreadthFitContent : TRBreadthFitContentPercent;
      ts->max.value = n.value;
      return YES;
    }
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
  if (singleOnly && n < 1) return NO;
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
  BOOL autoMinW, autoMinH;    /* content-based (automatic) minimum size in that axis */
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

/* A width or height as a border-box size: content-box sizes add the
   item's padding and border (percent padding against padRef). */
static inline TRValue TRZeroValue(void) { TRValue r = { 0, TRUnitPoint }; return r; }

static double TRGBox(const TRStyleStorage *s, TRValue v, double ref, BOOL horizontal, double padRef)
{
  double r = TRGResolve(v, ref);
  if (isnan(r)) return NAN;
  TREdge a = horizontal ? TREdgeLeft : TREdgeTop, b = horizontal ? TREdgeRight : TREdgeBottom;
  double pb = 0;
  TREdge es[2] = { a, b };
  for (int i = 0; i < 2; i++)
    {
      double pd = TRGResolve(s->padding[es[i]], padRef), bd = TRGResolve(s->border[es[i]], NAN);
      pb += (isnan(pd) ? 0 : MAX(0, pd)) + (isnan(bd) ? 0 : MAX(0, bd));
    }
  if (s->boxSizing == TRBoxSizingContentBox) return MAX(0, r) + pb;
  return MAX(r, pb);
}

static inline BOOL TRIsFitContent(TRBreadthKind k)
{
  return k == TRBreadthFitContent || k == TRBreadthFitContentPercent;
}

static double TRBreadthFixedValue(TRBreadth b, double avail)
{
  if (b.kind == TRBreadthFixed) return b.value;
  if (b.kind == TRBreadthPercent) return isnan(avail) ? NAN : b.value * avail / 100.0;
  return NAN;
}

/* Expands a template + auto-repeat into concrete tracks. */
static TRTrack *TRBuildTracks(NSString *tmpl, double avail, double gap, NSInteger *count,
                              NSInteger *autoFitStart, NSInteger *autoFitLen,
                              double minAvail, double maxAvail)
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
      /* CSS Grid 7.2.3.2: with an indefinite size, as many as fit in the
         max size, or else the fewest that reach the min size. */
      double room = !isnan(avail) ? avail : maxAvail;
      double per = groupSize + gap * l.groupLen;
      if (!isnan(room) && groupSize > 0)
        {
          double space = room - fixedOther - gap * others;
          reps = (int)floor((space + gap) / per);
          if (reps < 1) reps = 1;
        }
      else if (!isnan(minAvail) && groupSize > 0)
        {
          double space = minAvail - fixedOther - gap * others;
          reps = (int)ceil((space + gap) / per);
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

/* grid-auto-rows/columns: one or more sizes (no repeat()). Implicit
   tracks cycle through them: forwards after the explicit grid, backwards
   from the last before it. */
typedef struct { TRTrackSize sizes[16]; int count; } TRAutoTracks;

static TRAutoTracks TRAutoTrackSizes(NSString *autoTracks)
{
  TRAutoTracks at;
  at.count = 1;
  at.sizes[0] = (TRTrackSize){ { TRBreadthAuto, 0 }, { TRBreadthAuto, 0 } };
  if (autoTracks)
    {
      TRTrackList l;
      if (TRParseTrackList(autoTracks, &l, YES) && l.count > 0)
        {
          at.count = MIN(l.count, 16);
          for (int i = 0; i < at.count; i++) at.sizes[i] = l.entries[i].size;
        }
      free(l.entries);
    }
  return at;
}

static inline TRTrackSize TRAutoAfter(const TRAutoTracks *at, NSInteger k)    /* k-th track after */
{
  return at->sizes[k % at->count];
}

static inline TRTrackSize TRAutoBefore(const TRAutoTracks *at, NSInteger k)   /* k-th track before (0 = adjacent) */
{
  return at->sizes[at->count - 1 - (k % at->count)];
}

/* Line -> track index for one axis. Returns NO for auto. */
static BOOL TRResolveLine(TRLine l, NSString *name, NSInteger explicitCount, NSDictionary *areaLines,
                          BOOL isStart, NSInteger *out)
{
  if (l.kind == TRLineNumber)
    {
      /* Negative results are lines before the explicit grid; the caller
         adds implicit tracks there. */
      NSInteger idx = l.n > 0 ? l.n - 1 : explicitCount + 1 + l.n;
      *out = idx;
      return YES;
    }
  if (l.kind == TRLineName)
    {
      NSString *key = name;
      NSString *suffix = isStart ? @"-start" : @"-end";
      /* An area named exactly so comes first (its implicit name-start and
         name-end lines, CSS Grid 8.3.1); only then is a -start/-end
         suffix read as naming another area's edge. */
      if (areaLines[key] == nil && ([key hasSuffix: @"-start"] || [key hasSuffix: @"-end"]))
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
                         TRAlign contentAlign, double minAvail, double maxAvail)
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
            /* An automatic minimum is clamped so the margin box fits a fixed
               maximum track size (CSS Grid 6.6). */
            double minA = minC;
            double mg = columns ? it->margin[TREdgeLeft] + it->margin[TREdgeRight]
                                : it->margin[TREdgeTop] + it->margin[TREdgeBottom];
            TRValue autoSize = columns ? it->s->width : it->s->height;
            BOOL sizeAuto = autoSize.unit != TRUnitPoint && autoSize.unit != TRUnitPercent;
            if (mk == TRBreadthAuto && (columns ? it->autoMinW : it->autoMinH))
              {
                /* The content-box part is clamped to the stretch fit (the max
                   less margins, padding and border), which still count. */
                double fx = TRBreadthFixedValue(t->size.max, avail);
                double pb = TRGBox(it->s, TRZeroValue(), NAN, columns, NAN);
                if (!isnan(fx)) minA = MIN(minC - mg - pb, MAX(0, fx - mg - pb)) + mg + pb;
              }
            else if (mk == TRBreadthAuto && sizeAuto)
              {
                /* An explicit min-width/height replaces the automatic minimum:
                   the contribution is that size (a border box) plus margins. */
                TRValue mv = columns ? it->s->minWidth : it->s->minHeight;
                double mn = TRGBox(it->s, mv, NAN, columns, NAN);
                /* A percentage can't resolve while the tracks are sized: 0. */
                if (isnan(mn) && mv.unit == TRUnitPercent) mn = TRGBox(it->s, TRZeroValue(), NAN, columns, NAN);
                if (!isnan(mn)) minA = mn + mg;
              }
            if (mk == TRBreadthAuto) t->base = MAX(t->base, minA);
            else if (mk == TRBreadthMinContent)
              t->base = MAX(t->base, minC);
            else if (mk == TRBreadthMaxContent)
              t->base = MAX(t->base, maxC);
            TRBreadthKind xk = t->size.max.kind;
            if (xk == TRBreadthAuto || xk == TRBreadthMaxContent || TRIsFitContent(xk))
              { t->limit = limitSet[a] ? MAX(t->limit, maxC) : maxC; limitSet[a] = YES; }
            else if (xk == TRBreadthMinContent)
              { t->limit = limitSet[a] ? MAX(t->limit, minC) : minC; limitSet[a] = YES; }
          }
        else if (!crossesFlex)
          {
            /* A spanning item, in the phases of CSS Grid 12.5.1. */
            const double gapsS = gap * (span - 1);
            /* Its automatic minimum is clamped to the stretch fit when every
               spanned track has a fixed maximum (CSS Grid 6.6). */
            if (columns ? it->autoMinW : it->autoMinH)
              {
                double fixedSum = gapsS;
                BOOL allFixed = YES;
                for (NSInteger i = a; i < b && allFixed; i++)
                  {
                    double fx = TRBreadthFixedValue(tr[i].size.max, avail);
                    if (isnan(fx)) allFixed = NO; else fixedSum += fx;
                  }
                if (allFixed)
                  {
                    double mg = columns ? it->margin[TREdgeLeft] + it->margin[TREdgeRight]
                                        : it->margin[TREdgeTop] + it->margin[TREdgeBottom];
                    double pb = TRGBox(it->s, TRZeroValue(), NAN, columns, NAN);
                    minC = MIN(minC - mg - pb, MAX(0, fixedSum - mg - pb)) + mg + pb;
                  }
              }
            /* 1. Intrinsic minimums take its min-content contribution. */
            double have = gapsS;
            int intrinsic = 0;
            for (NSInteger i = a; i < b; i++)
              {
                have += tr[i].base;
                TRBreadthKind mk = tr[i].size.min.kind;
                if (mk == TRBreadthAuto || mk == TRBreadthMinContent || mk == TRBreadthMaxContent) intrinsic++;
              }
            double extra = minC - have;
            if (intrinsic > 0 && extra > 0)
              for (NSInteger i = a; i < b; i++)
                {
                  TRBreadthKind mk = tr[i].size.min.kind;
                  if (mk == TRBreadthAuto || mk == TRBreadthMinContent || mk == TRBreadthMaxContent)
                    tr[i].base += extra / intrinsic;
                }
            /* 2. Max-content minimums take its max-content contribution. */
            {
              int mcTracks = 0;
              double haveB = gapsS;
              for (NSInteger i = a; i < b; i++)
                {
                  haveB += tr[i].base;
                  if (tr[i].size.min.kind == TRBreadthMaxContent) mcTracks++;
                }
              double extraM = maxC - haveB;
              if (mcTracks > 0 && extraM > 0)
                for (NSInteger i = a; i < b; i++)
                  if (tr[i].size.min.kind == TRBreadthMaxContent)
                    tr[i].base += extraM / mcTracks;
            }
            /* 3. Growth limits, from the bases as they are now; a limit is
               never below its base. Intrinsic maximums take the min-content
               contribution, then max-content/auto/fit-content maximums take
               the max-content contribution. */
            for (int phase = 0; phase < 2; phase++)
              {
                double target = phase == 0 ? minC : maxC;
                double haveL = gapsS;
                int nTracks = 0;
                for (NSInteger i = a; i < b; i++)
                  {
                    haveL += (limitSet[i] && !isinf(tr[i].limit)) ? MAX(tr[i].limit, tr[i].base) : tr[i].base;
                    TRBreadthKind xk = tr[i].size.max.kind;
                    BOOL takes = phase == 0
                      ? (xk == TRBreadthAuto || xk == TRBreadthMaxContent || xk == TRBreadthMinContent || TRIsFitContent(xk))
                      : (xk == TRBreadthAuto || xk == TRBreadthMaxContent || TRIsFitContent(xk));
                    if (takes) nTracks++;
                  }
                double extraL = target - haveL;
                if (nTracks == 0 || extraL <= 0) continue;
                for (NSInteger i = a; i < b; i++)
                  {
                    TRBreadthKind xk = tr[i].size.max.kind;
                    BOOL takes = phase == 0
                      ? (xk == TRBreadthAuto || xk == TRBreadthMaxContent || xk == TRBreadthMinContent || TRIsFitContent(xk))
                      : (xk == TRBreadthAuto || xk == TRBreadthMaxContent || TRIsFitContent(xk));
                    if (!takes) continue;
                    double cur = (limitSet[i] && !isinf(tr[i].limit)) ? MAX(tr[i].limit, tr[i].base) : tr[i].base;
                    tr[i].limit = cur + extraL / nTracks;
                    limitSet[i] = YES;
                  }
              }
          }
      }
  for (NSInteger i = 0; i < n; i++)
    {
      if (!limitSet[i] && tr[i].size.max.kind != TRBreadthFr) tr[i].limit = tr[i].base;
      TRBreadthKind xk = tr[i].size.max.kind;
      if (TRIsFitContent(xk))
        {
          /* Capped at N; a percentage of an indefinite size leaves it uncapped. */
          double cap = xk == TRBreadthFitContent ? tr[i].size.max.value
            : (isnan(avail) ? INFINITY : tr[i].size.max.value * avail / 100.0);
          tr[i].limit = MIN(tr[i].limit, cap);
        }
      if (tr[i].limit < tr[i].base) tr[i].limit = tr[i].base;
    }

  double gaps = 0;
  NSInteger visible = 0;
  for (NSInteger i = 0; i < n; i++) if (!tr[i].collapsed) visible++;
  gaps = visible > 1 ? gap * (visible - 1) : 0;

  /* Maximise (CSS Grid 12.6). With an indefinite size (a max-content
     measurement) the free space is infinite: every track grows to its
     growth limit. Min-content measurements come in with a definite 0. */
  if (isnan(avail))
    for (NSInteger i = 0; i < n; i++)
      {
        if (tr[i].size.max.kind != TRBreadthFr && !isinf(tr[i].limit) && tr[i].limit > tr[i].base)
          tr[i].base = tr[i].limit;
      }
  else
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
      /* "Find the size of an fr" in a definite space. */
      double (^frFor)(double) = ^double(double space) {
          double fs = 0;
          BOOL inflexible[n ? n : 1];
          for (NSInteger i = 0; i < n; i++) inflexible[i] = (tr[i].size.max.kind != TRBreadthFr) || tr[i].collapsed;
          for (int guard = 0; guard < 16; guard++)
            {
              double leftover = space - gaps, sumFr = 0;
              for (NSInteger i = 0; i < n; i++)
                {
                  if (inflexible[i]) leftover -= tr[i].base;
                  else sumFr += tr[i].size.max.value;
                }
              if (sumFr <= 0) break;
              fs = MAX(0, leftover) / MAX(1.0, sumFr);
              BOOL changed = NO;
              for (NSInteger i = 0; i < n; i++)
                if (!inflexible[i] && tr[i].size.max.value * fs < tr[i].base)
                  { inflexible[i] = YES; changed = YES; }
              if (!changed) break;
            }
          return fs;
      };
      if (!isnan(avail))
        frSize = frFor(avail);
      else
        {
          /* Indefinite: the largest of each flexible track's base (divided
             by its flex factor when that is above 1) and each item's
             max-content over its flexible tracks (CSS Grid 12.7.1). */
          for (NSInteger i = 0; i < n; i++)
            if (tr[i].size.max.kind == TRBreadthFr && tr[i].size.max.value > 0)
              frSize = MAX(frSize, tr[i].base / MAX(1.0, tr[i].size.max.value));
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
          /* If that would make the grid larger than its max (smaller than
             its min), redo it with that size as definite space. */
          double total = gaps;
          for (NSInteger i = 0; i < n; i++)
            total += (tr[i].size.max.kind == TRBreadthFr && !tr[i].collapsed)
              ? MAX(tr[i].base, tr[i].size.max.value * frSize) : tr[i].base;
          if (!isnan(maxAvail) && total > maxAvail) frSize = frFor(maxAvail);
          else if (!isnan(minAvail) && total < minAvail) frSize = frFor(minAvail);
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
static double TRPlaceTracks(TRTrack *tr, NSInteger n, double gap, double avail, TRAlign align, BOOL safe)
{
  double total = 0;
  NSInteger visible = 0;
  for (NSInteger i = 0; i < n; i++) if (!tr[i].collapsed) { total += tr[i].base; visible++; }
  total += visible > 1 ? gap * (visible - 1) : 0;
  double free = isnan(avail) ? 0 : avail - total;
  if (safe && free < 0) align = TRAlignStart;   /* safe: overflow aligns as start */
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
  /* The grid's own min/max as inner sizes (NAN = none), which bound fr
     tracks in an indefinite space. */
  double mxW = TRGBox(s, s->maxWidth, ow, YES, ow), mnW = TRGBox(s, s->minWidth, ow, YES, ow);
  double mxH = TRGBox(s, s->maxHeight, oh, NO, ow), mnH = TRGBox(s, s->minHeight, oh, NO, ow);
  const double minInnerW = isnan(mnW) ? NAN : MAX(0, mnW - pbW), minInnerH = isnan(mnH) ? NAN : MAX(0, mnH - pbH);
  /* A min larger than the max wins (CSS 2.1 10.4/10.7). */
  const double maxInnerW = isnan(mxW) ? NAN : MAX(MAX(0, mxW - pbW), isnan(minInnerW) ? 0 : minInnerW);
  const double maxInnerH = isnan(mxH) ? NAN : MAX(MAX(0, mxH - pbH), isnan(minInnerH) ? 0 : minInnerH);

  /* ---- Explicit grid ---- */
  NSInteger nCols = 0, nRows = 0, fitStartC, fitLenC, fitStartR, fitLenR;
  TRTrack *colsT = TRBuildTracks(st->_gridTemplateColumns, innerW, colGap, &nCols, &fitStartC, &fitLenC, minInnerW, maxInnerW);
  TRTrack *rowsT = TRBuildTracks(st->_gridTemplateRows, innerH, rowGap, &nRows, &fitStartR, &fitLenR, minInnerH, maxInnerH);
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
      const TRStyleStorage *cs = TRChildStyle(c, dir);
      if (TRNodeIsNone(c)) continue;
      if (cs->position == TRPositionAbsolute) continue;
      items[n].node = c; items[n].s = cs; items[n].docOrder = (NSInteger)i;
      n++;
    }
  if (n > 1) qsort(items, (size_t)n, sizeof(TRGridItem), TRCompareItemOrder);

  BOOL colFlow = s->gridAutoFlowColumn;
  const BOOL dense = s->gridAutoFlowDense;
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
          else if (eDef) { span = a.kind == TRLineSpan ? a.n : 1; start = ei - span; def = YES; }
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
  /* Lines before the explicit grid (CSS Grid 8.3): implicit tracks are
     added there, and every placement shifts by their count. */
  NSInteger offR = 0, offC = 0;
  for (NSInteger k = 0; k < n; k++)
    {
      if (pl[k].rDef) offR = MAX(offR, -pl[k].rs);
      if (pl[k].cDef) offC = MAX(offC, -pl[k].cs);
    }
  if (offR > 0 || offC > 0)
    {
      NSInteger minorNeed = occMinor + (colFlow ? offR : offC);
      for (NSInteger k = 0; k < n; k++)
        {
          if (pl[k].rDef) pl[k].rs += offR;
          if (pl[k].cDef) pl[k].cs += offC;
          NSInteger minorEnd = colFlow ? (pl[k].rDef ? pl[k].rs + pl[k].rspan : pl[k].rspan)
                                       : (pl[k].cDef ? pl[k].cs + pl[k].cspan : pl[k].cspan);
          minorNeed = MAX(minorNeed, minorEnd);
        }
      occ = [NSMutableData data];   /* nothing is marked yet */
      occMinor = minorNeed;
      gridRows += offR; gridCols += offC;
    }

  /* 1. fully definite items */
  for (NSInteger k = 0; k < n; k++)
    if (pl[k].rDef && pl[k].cDef)
      {
        NSInteger maj = colFlow ? pl[k].cs : pl[k].rs, min = colFlow ? pl[k].rs : pl[k].cs;
        NSInteger ms = colFlow ? pl[k].cspan : pl[k].rspan, ns = colFlow ? pl[k].rspan : pl[k].cspan;
        mark(maj, min, ms, ns);
      }
  /* Widens the minor axis (adds implicit tracks), keeping the marks. */
  void (^widen)(NSInteger) = ^(NSInteger minorEnd) {
    if (minorEnd <= occMinor) return;
    NSInteger rowsHave = [occ length] / (occMinor ? occMinor : 1);
    NSMutableData *n2 = [NSMutableData dataWithLength: rowsHave * minorEnd];
    for (NSInteger r = 0; r < rowsHave; r++)
      memcpy((char *)[n2 mutableBytes] + r * minorEnd, (char *)[occ bytes] + r * occMinor, occMinor);
    occ = n2;
    occMinor = minorEnd;
  };

  /* 2. items locked to a major line (CSS Grid 8.5 step 2), in order: each
     goes past the previous one placed in its line, adding minor tracks
     when it runs out. */
  NSMutableDictionary *lineCursor = [NSMutableDictionary dictionary];
  for (NSInteger k = 0; k < n; k++)
    {
      if (pl[k].rDef && pl[k].cDef) continue;
      BOOL majDef = colFlow ? pl[k].cDef : pl[k].rDef;
      if (!majDef) continue;
      NSInteger maj = colFlow ? pl[k].cs : pl[k].rs;
      NSInteger majSpan = colFlow ? pl[k].cspan : pl[k].rspan, minSpan = colFlow ? pl[k].rspan : pl[k].cspan;
      /* dense: search from the start of the line, not past earlier items. */
      NSInteger min = dense ? 0 : [lineCursor[@(maj)] integerValue];
      for (;;)
        {
          widen(min + minSpan);
          if (fits(maj, min, majSpan, minSpan)) break;
          min++;
        }
      mark(maj, min, majSpan, minSpan);
      lineCursor[@(maj)] = @(min + minSpan);
      if (colFlow) { pl[k].rs = min; } else { pl[k].cs = min; }
      if (colFlow) pl[k].rDef = YES; else pl[k].cDef = YES;   /* placed */
    }

  /* 3. the rest, in order, with a sparse cursor */
  NSInteger curMaj = 0, curMin = 0;
  for (NSInteger k = 0; k < n; k++)
    {
      if (pl[k].rDef && pl[k].cDef) continue;
      BOOL majDef = colFlow ? pl[k].cDef : pl[k].rDef;
      BOOL minDef = colFlow ? pl[k].rDef : pl[k].cDef;
      NSInteger majStart = colFlow ? pl[k].cs : pl[k].rs, minStart = colFlow ? pl[k].rs : pl[k].cs;
      NSInteger majSpan = colFlow ? pl[k].cspan : pl[k].rspan, minSpan = colFlow ? pl[k].rspan : pl[k].cspan;
      NSInteger maj, min;
      if (dense) { curMaj = 0; curMin = 0; }   /* dense: every search starts at the beginning */
      if (majDef)
        {
          maj = majStart;   /* not reached: placed in step 2 */
          min = 0;
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
  TRAutoTracks autoCols = TRAutoTrackSizes(st->_gridAutoColumns), autoRows = TRAutoTrackSizes(st->_gridAutoRows);
  for (int axis = 0; axis < 2; axis++)
    {
      NSInteger off = axis == 0 ? offR : offC;
      if (off <= 0) continue;
      TRTrack **tp = axis == 0 ? &rowsT : &colsT;
      NSInteger *np = axis == 0 ? &nRows : &nCols;
      TRTrack *nt = calloc((size_t)(*np + off), sizeof(TRTrack));
      for (NSInteger i = 0; i < off; i++)
        nt[i].size = TRAutoBefore(axis == 0 ? &autoRows : &autoCols, off - 1 - i);
      if (*np) memcpy(nt + off, *tp, sizeof(TRTrack) * (size_t)*np);
      free(*tp);
      *tp = nt;
      *np += off;
      if (axis == 0) { if (fitStartR >= 0) fitStartR += off; }
      else { if (fitStartC >= 0) fitStartC += off; }
    }
  if (gridCols > nCols)
    {
      colsT = realloc(colsT, sizeof(TRTrack) * gridCols);
      for (NSInteger i = nCols; i < gridCols; i++)
        { memset(&colsT[i], 0, sizeof(TRTrack)); colsT[i].size = TRAutoAfter(&autoCols, i - nCols); }
      nCols = gridCols;
    }
  if (gridRows > nRows)
    {
      rowsT = realloc(rowsT, sizeof(TRTrack) * (gridRows ? gridRows : 1));
      for (NSInteger i = nRows; i < gridRows; i++)
        { memset(&rowsT[i], 0, sizeof(TRTrack)); rowsT[i].size = TRAutoAfter(&autoRows, i - nRows); }
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
          /* Percentages resolve against the grid area's width, which isn't
             known yet: they count as 0 while the columns are sized. */
          double m = TRGResolve(cs->margin[e], NAN);
          it->margin[e] = isnan(m) ? 0 : m;
        }
      double mh = it->margin[TREdgeLeft] + it->margin[TREdgeRight];
      it->autoMinW = cs->width.unit != TRUnitPoint && cs->width.unit != TRUnitPercent && cs->minWidth.unit == TRUnitAuto;
      it->autoMinH = cs->height.unit != TRUnitPoint && cs->height.unit != TRUnitPercent && cs->minHeight.unit == TRUnitAuto;
      double sw = TRGBox(cs, cs->width, NAN, YES, NAN);
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
  /* Percentage columns in a grid whose width depends on its tracks (CSS
     Grid 7.2.1): sized as auto to find the width, then resolved against
     it; the grid keeps that width. */
  BOOL percentCols = NO;
  TRTrackSize savedCols[nCols ? nCols : 1];
  if (wm != TRMeasureModeExactly)
    for (NSInteger i = 0; i < nCols; i++)
      {
        savedCols[i] = colsT[i].size;
        if (colsT[i].size.min.kind == TRBreadthPercent) { colsT[i].size.min.kind = TRBreadthAuto; percentCols = YES; }
        if (colsT[i].size.max.kind == TRBreadthPercent) { colsT[i].size.max.kind = TRBreadthAuto; percentCols = YES; }
      }
  TRSizeTracks(colsT, nCols, innerW, colGap, items, n, YES, s->justifyContent, minInnerW, maxInnerW);
  double contentW = NAN;
  if (percentCols)
    {
      double used = 0;
      NSInteger vis = 0;
      for (NSInteger i = 0; i < nCols; i++) if (!colsT[i].collapsed) { used += colsT[i].base; vis++; }
      used += vis > 1 ? colGap * (vis - 1) : 0;
      contentW = isnan(innerW) ? used : MIN(innerW, used);
      if (!isnan(minInnerW)) contentW = MAX(contentW, minInnerW);
      if (!isnan(maxInnerW)) contentW = MIN(contentW, maxInnerW);
      for (NSInteger i = 0; i < nCols; i++) colsT[i].size = savedCols[i];
      TRSizeTracks(colsT, nCols, contentW, colGap, items, n, YES, s->justifyContent, minInnerW, maxInnerW);
    }
  /* left/right are physical: columns are placed from the inline start and
     mirrored for rtl, where left is the end and right the start. */
  TRAlign colAlign = s->justifyContent;
  if (colAlign == TRAlignLeft) colAlign = rtl ? TRAlignEnd : TRAlignStart;
  else if (colAlign == TRAlignRight) colAlign = rtl ? TRAlignStart : TRAlignEnd;
  double colsTotal = TRPlaceTracks(colsT, nCols, colGap, isnan(contentW) ? innerW : contentW, colAlign, s->justifyContentSafe);
  if (!isnan(contentW)) colsTotal = contentW;

  /* Percentage margins, against each item's grid-area width (CSS Grid 6.5). */
  for (NSInteger k = 0; k < n; k++)
    {
      TRGridItem *it = &items[k];
      double areaW = TRSpanSize(colsT, it->c0, it->c1);
      for (int e = 0; e < 4; e++)
        if (it->s->margin[e].unit == TRUnitPercent)
          it->margin[e] = TRGResolve(it->s->margin[e], areaW);
    }

  /* ---- Row contributions: content height at the resolved column width ---- */
  for (NSInteger k = 0; k < n; k++)
    {
      TRGridItem *it = &items[k];
      const TRStyleStorage *cs = it->s;
      double areaW = TRSpanSize(colsT, it->c0, it->c1);
      double mh = it->margin[TREdgeLeft] + it->margin[TREdgeRight];
      double mv = it->margin[TREdgeTop] + it->margin[TREdgeBottom];
      double sh = TRGBox(cs, cs->height, NAN, NO, NAN);
      if (!isnan(sh)) { it->h = sh + mv; continue; }
      TRAlign js = cs->justifySelf == TRAlignAuto ? s->justifyItems : cs->justifySelf;
      double sw = TRGBox(cs, cs->width, areaW, YES, areaW);
      BOOL stretchW = isnan(sw) && (js == TRAlignNormal || js == TRAlignStretch)
                      && !it->marginAuto[TREdgeLeft] && !it->marginAuto[TREdgeRight];
      double w = !isnan(sw) ? sw : MAX(0, areaW - mh);
      TRSize sz = TRLayoutNode(it->node, w, NAN, (stretchW || !isnan(sw)) ? TRMeasureModeExactly : TRMeasureModeAtMost,
                               TRMeasureModeUndefined, areaW, NAN, NO, dir);
      it->h = sz.height + mv;
    }
  /* Percentage rows in a grid of indefinite height (CSS Grid 7.2.1): size
     them as auto to find the grid's height, then resolve them against that
     height and size the rows again. The grid keeps the first height. */
  BOOL percentRows = NO;
  TRTrackSize savedRows[nRows ? nRows : 1];
  if (isnan(innerH))
    for (NSInteger i = 0; i < nRows; i++)
      {
        savedRows[i] = rowsT[i].size;
        if (rowsT[i].size.min.kind == TRBreadthPercent) { rowsT[i].size.min.kind = TRBreadthAuto; percentRows = YES; }
        if (rowsT[i].size.max.kind == TRBreadthPercent) { rowsT[i].size.max.kind = TRBreadthAuto; percentRows = YES; }
      }
  TRSizeTracks(rowsT, nRows, innerH, rowGap, items, n, NO, s->alignContent, minInnerH, maxInnerH);
  double rowsTotal = TRPlaceTracks(rowsT, nRows, rowGap, innerH, s->alignContent, s->alignContentSafe);
  double contentH = rowsTotal;
  if (percentRows)
    {
      for (NSInteger i = 0; i < nRows; i++) rowsT[i].size = savedRows[i];
      TRSizeTracks(rowsT, nRows, contentH, rowGap, items, n, NO, s->alignContent, minInnerH, maxInnerH);
      rowsTotal = TRPlaceTracks(rowsT, nRows, rowGap, contentH, s->alignContent, s->alignContentSafe);
    }
  /* A percentage row-gap in an indefinite height counts as 0 while the
     height is found, then resolves against it (the grid keeps that height,
     so the rows may overflow). */
  if (isnan(innerH) && s->rowGap.unit == TRUnitPercent)
    {
      double g = MAX(0, s->rowGap.value * contentH / 100.0);
      rowsTotal = TRPlaceTracks(rowsT, nRows, g, contentH, s->alignContent, s->alignContentSafe);
    }

  /* ---- Container size ---- */
  double W = wm == TRMeasureModeExactly ? aw : colsTotal + pbW;
  if (wm == TRMeasureModeAtMost) W = MIN(aw, W);
  double H = hm == TRMeasureModeExactly ? ah : contentH + pbH;
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
          double sw = TRGBox(cs, cs->width, areaW, YES, areaW), sh = TRGBox(cs, cs->height, areaH, NO, areaW);
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
          double minw = TRGBox(cs, cs->minWidth, areaW, YES, areaW), maxw = TRGBox(cs, cs->maxWidth, areaW, YES, areaW);
          if (!isnan(maxw)) w = MIN(w, maxw);
          if (!isnan(minw)) w = MAX(w, minw);
          if (!isnan(sh)) h = sh;
          else if ((as == TRAlignNormal || as == TRAlignStretch) && !autoT && !autoB && isnan(ar)) h = MAX(0, areaH - mv);
          else
            {
              TRSize sz = TRLayoutNode(it->node, w, NAN, TRMeasureModeExactly, TRMeasureModeUndefined, areaW, areaH, NO, dir);
              h = sz.height;
            }
          double minh = TRGBox(cs, cs->minHeight, areaH, NO, areaW), maxh = TRGBox(cs, cs->maxHeight, areaH, NO, areaW);
          if (!isnan(maxh)) h = MIN(h, maxh);
          if (!isnan(minh)) h = MAX(h, minh);

          double freeW = areaW - mh - w, freeH = areaH - mv - h;
          /* x is computed from the inline start and mirrored for rtl, so
             the start-side margin is the right one there. */
          if (rtl) { BOOL t = autoL; autoL = autoR; autoR = t; }
          double offX = rtl ? it->margin[TREdgeRight] : it->margin[TREdgeLeft], offY = it->margin[TREdgeTop];
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
          if (it->s->position == TRPositionRelative)
            {
              /* Relative offsets, against the grid area (CSS Grid 9). With
                 both left and right, the grid's direction picks. */
              double l = TRGResolve(it->s->inset[TREdgeLeft], areaW), r = TRGResolve(it->s->inset[TREdgeRight], areaW);
              double t = TRGResolve(it->s->inset[TREdgeTop], areaH), b = TRGResolve(it->s->inset[TREdgeBottom], areaH);
              if (!isnan(l) && !(rtl && !isnan(r))) x += l;
              else if (!isnan(r)) x -= r;
              y += !isnan(t) ? t : (!isnan(b) ? -b : 0);
            }
          TRLayoutNode(it->node, w, h, TRMeasureModeExactly, TRMeasureModeExactly, areaW, areaH, YES, dir);
          TRNode *c = it->node;
          c->_rawFrame = TRRectMake(x, y, w, h);
          c->_lineIndex = it->r0 == 0 ? 0 : 1;
          for (int e = 0; e < 4; e++) c->_lmargin[e] = it->margin[e];
          maxX = MAX(maxX, x + w + it->margin[TREdgeRight]);
          maxY = MAX(maxY, y + h + it->margin[TREdgeBottom]);
        }
      /* Absolutely positioned children (CSS Grid 9.1): the containing block
         is the grid area named by grid-row/grid-column. An auto line, or a
         line outside the grid, is the padding edge; a start line is the
         start of the track after it and an end line the end of the track
         before it, so gutters are excluded. */
      /* Lines only exist for tracks that really exist: explicit ones and
         those in-flow items occupy (placement always keeps one column). */
      NSInteger realRows = MIN(nRows, offR + explicitRows), realCols = MIN(nCols, offC + explicitCols);
      for (NSInteger k = 0; k < n; k++)
        {
          realRows = MAX(realRows, items[k].r1);
          realCols = MAX(realCols, items[k].c1);
        }
      for (NSUInteger i = 0; i < nc; i++)
        {
          TRNode *c = children[i];
          const TRStyleStorage *cs = TRChildStyle(c, dir);
          if (TRNodeIsNone(c) || cs->position != TRPositionAbsolute) continue;
          TRStyle *cst = c->_style;
          double cbStart[2], cbEnd[2];   /* [0] rows (y), [1] columns (x); border-box coordinates */
          for (int axis = 0; axis < 2; axis++)
            {
              TRTrack *tr = axis == 0 ? rowsT : colsT;
              NSInteger nt = axis == 0 ? realRows : realCols;
              double origin = axis == 0 ? pad[TREdgeTop] + border[TREdgeTop]
                                        : pad[TREdgeLeft] + border[TREdgeLeft];
              double padStart = axis == 0 ? border[TREdgeTop] : border[TREdgeLeft];
              double padEnd = axis == 0 ? H - border[TREdgeBottom] : W - border[TREdgeRight];
              NSString *sv = axis == 0 ? cst->_gridRowStart : cst->_gridColumnStart;
              NSString *ev = axis == 0 ? cst->_gridRowEnd : cst->_gridColumnEnd;
              NSString *aName = nil, *bName = nil;
              TRLine a, b;
              TRParseLine(sv, &a, &aName);
              TRParseLine(ev, &b, &bName);
              NSInteger expl = axis == 0 ? explicitRows : explicitCols;
              NSDictionary *names = axis == 0 ? rowLines : colLines;
              NSInteger si = 0, ei = 0;
              BOOL sDef = TRResolveLine(a, aName, expl, names, YES, &si);
              BOOL eDef = TRResolveLine(b, bName, expl, names, NO, &ei);
              NSInteger off = axis == 0 ? offR : offC;
              si += off; ei += off;
              if (sDef && !eDef && b.kind == TRLineSpan) { ei = si + b.n; eDef = YES; }
              if (eDef && !sDef && a.kind == TRLineSpan) { si = ei - a.n; sDef = si >= 0; }
              if (sDef && eDef && ei < si) { NSInteger t = si; si = ei; ei = t; }
              if (sDef && (si < 0 || si > nt)) sDef = NO;
              if (eDef && (ei < 0 || ei > nt)) eDef = NO;
              /* si/ei are in 0..nt when defined (checked above). */
              double sp = !sDef ? 0 : (si < nt ? tr[si].pos : (nt ? tr[nt - 1].pos + tr[nt - 1].base : 0));
              double ep = !eDef ? 0 : (ei == 0 ? (nt ? tr[0].pos : 0) : tr[ei - 1].pos + tr[ei - 1].base);
              if (axis == 1 && rtl)
                {
                  /* Columns run right to left: the start line is the right edge. */
                  double inner = W - pbW;
                  cbStart[axis] = !eDef ? padStart : origin + inner - ep;
                  cbEnd[axis] = !sDef ? padEnd : origin + inner - sp;
                }
              else
                {
                  cbStart[axis] = !sDef ? padStart : origin + sp;
                  cbEnd[axis] = !eDef ? padEnd : origin + ep;
                }
              if (cbEnd[axis] < cbStart[axis]) cbEnd[axis] = cbStart[axis];
            }
          double cbX = cbStart[1], cbY = cbStart[0];
          double cbW = cbEnd[1] - cbStart[1], cbH = cbEnd[0] - cbStart[0];
          double L = TRGResolve(cs->inset[TREdgeLeft], cbW), R = TRGResolve(cs->inset[TREdgeRight], cbW);
          double T = TRGResolve(cs->inset[TREdgeTop], cbH), B = TRGResolve(cs->inset[TREdgeBottom], cbH);
          double w = TRGBox(cs, cs->width, cbW, YES, cbW), h = TRGBox(cs, cs->height, cbH, NO, cbW);
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
          /* Over-constrained (both insets and a width): the containing
             block's direction decides, so rtl keeps right (CSS 2 10.3.7). */
          BOOL useRight = !isnan(R) && (isnan(L) || rtl);
          double x = useRight ? cbX + cbW - R - w : (!isnan(L) ? cbX + L : (rtl ? cbX + cbW - w : cbX));
          double y = !isnan(T) ? cbY + T : (!isnan(B) ? cbY + cbH - B - h : cbY);
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
