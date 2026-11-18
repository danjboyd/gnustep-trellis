/* TRLint.m - layout checks over a frames.json tree.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRLint.h"
#import <math.h>

static const double kTol = 0.5;

static NSString *TRNodeName(NSDictionary *n, NSString *path)
{
  NSString *ident = n[@"id"];
  NSString *cls = n[@"class"] ?: @"box";
  return ident ? [NSString stringWithFormat: @"#%@", ident]
               : [NSString stringWithFormat: @"%@ at %@", cls, path];
}

static void TRAdd(NSMutableArray *out, NSString *rule, NSString *sev, NSDictionary *n,
                  NSString *path, NSString *msg)
{
  NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary: @{
    @"rule": rule, @"severity": sev, @"path": path, @"message": msg}];
  if (n[@"id"]) d[@"id"] = n[@"id"];
  [out addObject: d];
}

static void TRLintNode(NSDictionary *n, NSString *path, double absX, double absY,
                       double vw, double vh, BOOL insideScroller, NSMutableArray *out)
{
  if ([n[@"hidden"] boolValue]) return;
  double x = [n[@"x"] doubleValue], y = [n[@"y"] doubleValue];
  double w = [n[@"width"] doubleValue], h = [n[@"height"] doubleValue];
  double ax = absX + x, ay = absY + y;
  NSString *name = TRNodeName(n, path);

  NSDictionary *needed = n[@"needed"];
  NSDictionary *intrinsic = n[@"intrinsic"];
  if (needed && n[@"text"])
    {
      double nw = [needed[@"width"] doubleValue], nh = [needed[@"height"] doubleValue];
      if (nw > w + kTol || nh > h + kTol)
        TRAdd(out, @"clipped-text", @"error", n, path,
              [NSString stringWithFormat: @"%@: text needs %gx%g, has %gx%g",
                        name, ceil(nw), ceil(nh), w, h]);
    }
  else if (intrinsic)
    {
      double iw = [intrinsic[@"width"] doubleValue], ih = [intrinsic[@"height"] doubleValue];
      /* An editable field's intrinsic width (Cocoa: its placeholder) isn't
         a minimum; only its height is checked. */
      if ([n[@"editable"] boolValue]) iw = 0;
      if (iw > w + kTol || ih > h + kTol)
        TRAdd(out, @"undersized", @"error", n, path,
              [NSString stringWithFormat: @"%@ (%@) is %gx%g, smaller than its intrinsic %gx%g",
                        name, n[@"class"], w, h, iw, ih]);
      /* ...so an editable field with no width or flex shrinks to a sliver. */
      else if ([n[@"editable"] boolValue] && w >= 1 && w < 40)
        TRAdd(out, @"narrow-field", @"warning", n, path,
              [NSString stringWithFormat: @"%@ (%@) is only %g wide: an editable field has no useful "
                        @"intrinsic width; give it a width, min-width or flex", name, n[@"class"], w]);
    }

  /* Fixed-height controls (push buttons, pop-ups, single-line fields)
     stretched far beyond their natural height: usually a flex-basis or
     align-items: stretch meant for the other axis. */
  NSString *cls = n[@"class"];
  if (intrinsic && !n[@"needed"] &&
      ([cls hasSuffix: @"Button"] || [cls hasSuffix: @"PopUpButton"] || [cls isEqualToString: @"NSTextField"]))
    {
      double ih = [intrinsic[@"height"] doubleValue];
      if (ih > 0 && h > ih * 1.5 + 4)
        TRAdd(out, @"stretched", @"warning", n, path,
              [NSString stringWithFormat: @"%@ (%@) is %g tall; its natural height is %g "
                        @"(check flex-basis/align-items for the cross axis)", name, cls, h, ih]);
    }

  /* A control laid out with no width or height is invisible: usually a
     view with no intrinsic size and no width/height/flex. */
  if (![cls isEqualToString: @"NSView"] && ![cls isEqualToString: @"TRBoxView"]
      && [n[@"children"] count] == 0 && (w < 1 || h < 1))
    TRAdd(out, @"collapsed", @"warning", n, path,
          [NSString stringWithFormat: @"%@ (%@) is %gx%g: give it a width/height or flex", name, cls, w, h]);

  if (!insideScroller && (ax < -kTol || ay < -kTol || (vw > 0 && ax + w > vw + kTol) || (vh > 0 && ay + h > vh + kTol)))
    TRAdd(out, @"offscreen", @"warning", n, path,
          [NSString stringWithFormat: @"%@ (%g,%g %gx%g) extends outside the %gx%g viewport",
                    name, ax, ay, w, h, vw, vh]);

  NSArray *kids = n[@"children"];
  NSString *ov = n[@"overflow"];
  BOOL clips = [ov isEqualToString: @"hidden"] || [ov isEqualToString: @"scroll"]
            || [ov isEqualToString: @"auto"];
  NSMutableArray *flow = [NSMutableArray array];
  for (NSUInteger i = 0; i < [kids count]; i++)
    {
      NSDictionary *c = kids[i];
      NSString *cp = [NSString stringWithFormat: @"%@/%lu", path, (unsigned long)i];
      if ([c[@"hidden"] boolValue]) continue;
      double cx = [c[@"x"] doubleValue], cy = [c[@"y"] doubleValue];
      double cw = [c[@"width"] doubleValue], ch = [c[@"height"] doubleValue];
      /* Pixel rounding rounds a measured (text) leaf's fractional size up,
         as Yoga does, so it may stick out of its parent by up to one
         pixel; that isn't a layout problem. */
      double far = c[@"intrinsic"] != nil ? 1.0 + kTol : kTol;
      if (!clips && (cx < -kTol || cy < -kTol || cx + cw > w + far || cy + ch > h + far))
        TRAdd(out, @"overflow", @"warning", c, cp,
              [NSString stringWithFormat: @"%@ (%g,%g %gx%g) overflows %@ (%gx%g)",
                        TRNodeName(c, cp), cx, cy, cw, ch, name, w, h]);
      if (![c[@"position"] isEqualToString: @"absolute"] && cw > 0 && ch > 0)
        [flow addObject: @[c, cp]];
      /* Content of a scrolling/clipping box may extend past the viewport. */
      TRLintNode(c, cp, ax, ay, vw, vh, insideScroller || clips, out);
    }
  for (NSUInteger i = 0; i < [flow count]; i++)
    for (NSUInteger j = i + 1; j < [flow count]; j++)
      {
        NSDictionary *a = flow[i][0], *b = flow[j][0];
        double ix = MIN([a[@"x"] doubleValue] + [a[@"width"] doubleValue],
                        [b[@"x"] doubleValue] + [b[@"width"] doubleValue])
                  - MAX([a[@"x"] doubleValue], [b[@"x"] doubleValue]);
        double iy = MIN([a[@"y"] doubleValue] + [a[@"height"] doubleValue],
                        [b[@"y"] doubleValue] + [b[@"height"] doubleValue])
                  - MAX([a[@"y"] doubleValue], [b[@"y"] doubleValue]);
        if (ix > kTol && iy > kTol)
          TRAdd(out, @"overlap", @"error", b, flow[j][1],
                [NSString stringWithFormat: @"%@ overlaps %@ by %gx%g",
                          TRNodeName(b, flow[j][1]), TRNodeName(a, flow[i][1]), ix, iy]);
      }
}

/* ---- Contrast of resolved colours ---- */

static BOOL TRParseHex(NSString *hex, double rgba[4])
{
  if (![hex hasPrefix: @"#"] || ([hex length] != 7 && [hex length] != 9)) return NO;
  unsigned v[4] = {0, 0, 0, 255};
  for (int i = 0; i < ([hex length] == 9 ? 4 : 3); i++)
    {
      unsigned x = 0;
      [[NSScanner scannerWithString: [hex substringWithRange: NSMakeRange(1 + 2 * i, 2)]] scanHexInt: &x];
      v[i] = x;
    }
  for (int i = 0; i < 4; i++) rgba[i] = v[i] / 255.0;
  return YES;
}

static double TRLuminance(const double c[3])
{
  double l[3];
  for (int i = 0; i < 3; i++)
    l[i] = c[i] <= 0.03928 ? c[i] / 12.92 : pow((c[i] + 0.055) / 1.055, 2.4);
  return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2];
}

/* WCAG contrast of text over a background (the text's alpha blended in). */
static double TRContrast(NSString *fg, NSString *bg)
{
  double f[4], b[4];
  if (!TRParseHex(fg, f) || !TRParseHex(bg, b)) return 21;
  double mixed[3];
  for (int i = 0; i < 3; i++) mixed[i] = f[i] * f[3] + b[i] * (1 - f[3]);
  double lf = TRLuminance(mixed), lb = TRLuminance(b);
  return (MAX(lf, lb) + 0.05) / (MIN(lf, lb) + 0.05);
}

/* Text with less than 3:1 contrast against the nearest background (the
   window background when no box sets one): typically a fixed background
   with text that follows the appearance, or the other way round. */
static void TRLintContrast(NSDictionary *n, NSString *path, NSString *under, NSMutableArray *out)
{
  if ([n[@"hidden"] boolValue]) return;
  NSString *bg = n[@"background"];
  double b[4];
  if (bg && TRParseHex(bg, b) && b[3] > 0.5) under = bg;   /* translucent: keep what's below */
  NSString *fg = n[@"textColor"];
  NSString *text = n[@"text"] ?: n[@"title"];
  if (fg && under && [text length] > 0)
    {
      double c = TRContrast(fg, under);
      if (c < 3.0)
        TRAdd(out, @"low-contrast", @"warning", n, path, [NSString stringWithFormat:
          @"%@: text %@ on %@ has contrast %.1f:1 (needs 3:1); use system colours (CanvasText on Canvas, GrayText)",
          TRNodeName(n, path), fg, under, c]);
    }
  NSArray *kids = n[@"children"];
  for (NSUInteger i = 0; i < [kids count]; i++)
    TRLintContrast(kids[i], [NSString stringWithFormat: @"%@/%lu", path, (unsigned long)i], under, out);
}

/* ---- Target size (WCAG 2.2, 2.5.8 minimum) ---- */

static const double kTarget = 24;

/* Targets with absolute frames, each tagged with its scope: the nearest
   scrolling or clipping ancestor (content inside a scroller only meets
   other content of that scroller; its off-screen part isn't over what's
   outside it). */
static void TRCollectTargets(NSDictionary *n, NSString *path, double ax, double ay, NSString *scope,
                             NSMutableArray *out)
{
  if ([n[@"hidden"] boolValue]) return;
  double x = ax + [n[@"x"] doubleValue], y = ay + [n[@"y"] doubleValue];
  if ([n[@"interactive"] boolValue])
    [out addObject: @{@"node": n, @"path": path, @"scope": scope,
                      @"x": @(x), @"y": @(y), @"w": n[@"width"] ?: @0, @"h": n[@"height"] ?: @0}];
  NSString *ov = n[@"overflow"];
  NSString *inner = ([ov isEqualToString: @"scroll"] || [ov isEqualToString: @"hidden"] || [ov isEqualToString: @"auto"])
    ? path : scope;
  NSArray *kids = n[@"children"];
  for (NSUInteger i = 0; i < [kids count]; i++)
    TRCollectTargets(kids[i], [NSString stringWithFormat: @"%@/%lu", path, (unsigned long)i], x, y, inner, out);
}

/* Distance from a point to a rectangle (0 inside). */
static double TRDistToRect(double px, double py, double x, double y, double w, double h)
{
  double dx = MAX(MAX(x - px, 0), px - (x + w)), dy = MAX(MAX(y - py, 0), py - (y + h));
  return sqrt(dx * dx + dy * dy);
}

/* A control smaller than 24x24 passes if a 24 px circle on its centre
   touches no other target, nor another small target's circle (the
   spacing exception). */
static void TRLintTargets(NSDictionary *root, NSMutableArray *out)
{
  NSMutableArray *t = [NSMutableArray array];
  TRCollectTargets(root, @"root", 0, 0, @"", t);
  for (NSUInteger i = 0; i < [t count]; i++)
    {
      NSDictionary *a = t[i];
      double aw = [a[@"w"] doubleValue], ah = [a[@"h"] doubleValue];
      if (aw <= 0 || ah <= 0 || (aw >= kTarget - kTol && ah >= kTarget - kTol)) continue;
      double cx = [a[@"x"] doubleValue] + aw / 2, cy = [a[@"y"] doubleValue] + ah / 2;
      NSDictionary *hit = nil;
      for (NSUInteger j = 0; j < [t count] && hit == nil; j++)
        {
          if (j == i) continue;
          NSDictionary *b = t[j];
          if (![b[@"scope"] isEqualToString: a[@"scope"]]) continue;
          double bw = [b[@"w"] doubleValue], bh = [b[@"h"] doubleValue];
          if (bw <= 0 || bh <= 0) continue;
          BOOL bSmall = bw < kTarget - kTol || bh < kTarget - kTol;
          double d = bSmall
            ? hypot(cx - ([b[@"x"] doubleValue] + bw / 2), cy - ([b[@"y"] doubleValue] + bh / 2))
            : TRDistToRect(cx, cy, [b[@"x"] doubleValue], [b[@"y"] doubleValue], bw, bh);
          if (d < (bSmall ? kTarget : kTarget / 2) - kTol) hit = b;
        }
      if (hit)
        TRAdd(out, @"touch-target", @"warning", a[@"node"], a[@"path"], [NSString stringWithFormat:
          @"%@ is %gx%g, under the 24x24 minimum, and too close to %@ (WCAG 2.5.8): make it at least 24 px, or space it out",
          TRNodeName(a[@"node"], a[@"path"]), aw, ah, TRNodeName(hit[@"node"], hit[@"path"])]);
    }
}

NSArray<NSDictionary *> *TRLintFrameTree(NSDictionary *root, double vw, double vh)
{
  NSMutableArray *out = [NSMutableArray array];
  TRLintNode(root, @"root", 0, 0, vw, vh, NO, out);
  TRLintContrast(root, @"root", root[@"windowBackground"], out);
  TRLintTargets(root, out);
  return out;
}
