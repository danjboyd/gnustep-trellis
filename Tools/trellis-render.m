/* trellis-render - lays out a Trellis screen offscreen and writes a PNG and
   a JSON frame dump (docs/design.md section 5).

   On GNUstep it refuses to run unless GNUSTEP_HOME points at a private
   directory and the user defaults resolve inside it, so it can never touch
   a real user's settings. Use scripts/run-headless.sh.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRViewMeasure.h"
#import "TRLint.h"

extern TRBoxView *TRSampleScreen(NSString *name);
extern NSArray<NSString *> *TRSampleScreenNames(void);

static void TRDie(int code, NSString *fmt, ...) NS_FORMAT_FUNCTION(2,3);
static void TRDie(int code, NSString *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  NSString *m = [[NSString alloc] initWithFormat: fmt arguments: ap];
  va_end(ap);
  fprintf(stderr, "trellis-render: %s\n", [m UTF8String]);
  exit(code);
}

/* Fail closed unless this process is isolated from real user settings. */
static void TRCheckIsolation(void)
{
#ifdef GNUSTEP
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  NSString *gh = env[@"GNUSTEP_HOME"];
  if ([gh length] == 0)
    TRDie(3, @"GNUSTEP_HOME is not set; refusing to run (use scripts/run-headless.sh)");
  gh = [gh stringByStandardizingPath];
  NSString *home = [NSHomeDirectory() stringByStandardizingPath];
  NSArray *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
  NSString *userLib = [[lib firstObject] stringByStandardizingPath];
  if (![home hasPrefix: gh] || userLib == nil || ![userLib hasPrefix: gh])
    TRDie(3, @"user home (%@) or Library (%@) is outside GNUSTEP_HOME (%@); refusing to run",
          home, userLib, gh);
  NSString *display = env[@"DISPLAY"];
  if ([display length] == 0 || [display isEqualToString: @":0"] || [display isEqualToString: @":0.0"])
    TRDie(3, @"DISPLAY is %@; trellis-render only runs on a private Xvfb display",
          display ?: @"unset");
#endif
}

/* ---- Frame dump ---- */

static NSDictionary *TRDumpView(NSView *v, TRNode *node)
{
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  NSString *ident = [v respondsToSelector: @selector(identifier)] ? [(id)v identifier] : nil;
  if ([ident length]) d[@"id"] = ident;
  d[@"class"] = NSStringFromClass([v class]);
  NSRect f = [v frame];
  d[@"x"] = @(f.origin.x);
  d[@"y"] = @(f.origin.y);
  d[@"width"] = @(f.size.width);
  d[@"height"] = @(f.size.height);
  if ([v isHidden]) d[@"hidden"] = @YES;
  if (node)
    {
      NSString *decl = [node.style declarationString];
      if ([decl length]) d[@"style"] = decl;
      if (node.style.position == TRPositionAbsolute) d[@"position"] = @"absolute";
      TROverflow ov = node.style.overflow;
      if (ov != TROverflowVisible)
        d[@"overflow"] = ov == TROverflowHidden ? @"hidden" : (ov == TROverflowScroll ? @"scroll" : @"auto");
      NSArray *m = node.matchedConditions;
      if ([m count]) d[@"container"] = @{@"matched": m};
    }
  if ([v isKindOfClass: [NSControl class]] && [(NSControl *)v cell] != nil)
    {
      NSCell *cell = [(NSControl *)v cell];
      NSSize ic = [cell cellSize];
      d[@"intrinsic"] = @{@"width": @(ceil(ic.width)), @"height": @(ceil(ic.height))};
      if ([cell type] == NSTextCellType && ![v isKindOfClass: [NSButton class]]
          && ![v isKindOfClass: [NSPopUpButton class]])
        {
          NSString *text = [cell stringValue];
          if ([text length])
            {
              d[@"text"] = text;
              NSSize need;
              TRViewIsClipped(v, &need);
              d[@"needed"] = @{@"width": @(ceil(need.width)), @"height": @(ceil(need.height))};
            }
        }
      else if ([v isKindOfClass: [NSButton class]])
        d[@"title"] = [(NSButton *)v title];
    }
  if ([v isKindOfClass: [TRBoxView class]])
    {
      TRBoxView *box = (TRBoxView *)v;
      NSMutableArray *kids = [NSMutableArray array];
      for (TRNode *c in box.node.children)
        {
          NSView *cv = c.context;
          if (cv) [kids addObject: TRDumpView(cv, c)];
        }
      if ([kids count]) d[@"children"] = kids;
    }
  return d;
}

/* ---- Outlines overlay ---- */

static void TROutline(NSView *v, NSPoint origin)
{
  if ([v isHidden]) return;
  NSRect f = [v frame];
  NSRect r = NSMakeRect(origin.x + f.origin.x, origin.y + f.origin.y, f.size.width, f.size.height);
  BOOL box = [v isKindOfClass: [TRBoxView class]];
  [(box ? [NSColor colorWithCalibratedRed: 0.1 green: 0.45 blue: 0.85 alpha: 0.8]
        : [NSColor colorWithCalibratedRed: 0.9 green: 0.3 blue: 0.1 alpha: 0.7]) set];
  NSFrameRectWithWidth(r, 1);
  if (box)
    for (NSView *c in [v subviews])
      TROutline(c, r.origin);
}

/* ---- Rendering ---- */

static NSData *TRRenderPNG(TRBoxView *box, BOOL outlines)
{
  NSRect b = [box bounds];
  [box display];
  NSBitmapImageRep *rep = [box bitmapImageRepForCachingDisplayInRect: b];
  [box cacheDisplayInRect: b toBitmapImageRep: rep];
  if (outlines)
    {
      NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep: rep];
      [NSGraphicsContext saveGraphicsState];
      [NSGraphicsContext setCurrentContext: ctx];
      /* Bitmap contexts are not flipped: flip so frames map directly. */
      NSAffineTransform *t = [NSAffineTransform transform];
      [t translateXBy: 0 yBy: NSHeight(b)];
      [t scaleXBy: 1 yBy: -1];
      [t concat];
      for (NSView *c in [box subviews]) TROutline(c, NSZeroPoint);
      [NSGraphicsContext restoreGraphicsState];
    }
  return [rep representationUsingType: NSPNGFileType properties: @{}];
}

static NSString *TRWithSuffix(NSString *path, NSString *suffix)
{
  if (suffix == nil) return path;
  NSString *ext = [path pathExtension];
  return [[[path stringByDeletingPathExtension] stringByAppendingFormat: @"-%@", suffix]
           stringByAppendingPathExtension: ext];
}

static void TRUsage(void)
{
  fprintf(stderr,
    "usage: trellis-render --screen NAME [--width W | --widths W1,W2,...] [--height H]\n"
    "                      [--png out.png] [--json out.json] [--outlines] [--lint]\n"
    "screens: %s\n", [[TRSampleScreenNames() componentsJoinedByString: @", "] UTF8String]);
  exit(2);
}

int main(int argc, const char **argv)
{
  @autoreleasepool
    {
      NSString *screen = nil, *png = nil, *json = nil;
      NSMutableArray *widths = [NSMutableArray array];
      double height = NAN;
      BOOL outlines = NO, printLint = NO;
      for (int i = 1; i < argc; i++)
        {
          NSString *a = [NSString stringWithUTF8String: argv[i]];
          NSString *next = (i + 1 < argc) ? [NSString stringWithUTF8String: argv[i + 1]] : nil;
          if ([a isEqualToString: @"--screen"] && next) { screen = next; i++; }
          else if ([a isEqualToString: @"--width"] && next) { [widths addObject: @([next doubleValue])]; i++; }
          else if ([a isEqualToString: @"--widths"] && next)
            {
              for (NSString *w in [next componentsSeparatedByString: @","])
                [widths addObject: @([w doubleValue])];
              i++;
            }
          else if ([a isEqualToString: @"--height"] && next) { height = [next doubleValue]; i++; }
          else if ([a isEqualToString: @"--png"] && next) { png = next; i++; }
          else if ([a isEqualToString: @"--json"] && next) { json = next; i++; }
          else if ([a isEqualToString: @"--outlines"]) outlines = YES;
          else if ([a isEqualToString: @"--lint"]) printLint = YES;
          else TRUsage();
        }
      if (screen == nil) TRUsage();
      if ([widths count] == 0) [widths addObject: @480];

      TRCheckIsolation();
      [NSApplication sharedApplication];

      int lintErrors = 0;
      for (NSNumber *wn in widths)
        {
          double W = [wn doubleValue];
          NSString *suffix = [widths count] > 1 ? [NSString stringWithFormat: @"%g", W] : nil;
          TRBoxView *box = TRSampleScreen(screen);
          if (box == nil) TRDie(2, @"unknown screen '%@'", screen);

          double H = height;
          if (isnan(H))
            {
              /* Content height at this width. */
              [box.node layoutWithAvailableSize: TRSizeMake(W, NAN)];
              H = ceil(box.node.layoutFrame.height);
            }
          NSWindow *win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, W, H)
                                                      styleMask: NSBorderlessWindowMask
                                                        backing: NSBackingStoreBuffered
                                                          defer: NO];
          [win setReleasedWhenClosed: NO];
          [win setContentView: box];
          [box setFrame: NSMakeRect(0, 0, W, H)];
          [box layoutTrellis];

          NSDictionary *tree = TRDumpView(box, box.node);
          NSArray *lint = TRLintFrameTree(tree, W, H);
          for (NSDictionary *f in lint)
            {
              if ([f[@"severity"] isEqualToString: @"error"]) lintErrors++;
              if (printLint)
                printf("%s %s [%s] %s\n", [suffix ?: @"" UTF8String], [f[@"severity"] UTF8String],
                       [f[@"rule"] UTF8String], [f[@"message"] UTF8String]);
            }
          if (json)
            {
              NSDictionary *doc = @{
                @"trellis": @"0.1", @"source": [NSString stringWithFormat: @"sample:%@", screen],
                @"viewport": @{@"width": @(W), @"height": @(H), @"scale": @1},
                @"root": tree, @"lint": lint };
              NSData *data = [NSJSONSerialization dataWithJSONObject: doc
                                                             options: NSJSONWritingPrettyPrinted error: NULL];
              if (![data writeToFile: TRWithSuffix(json, suffix) atomically: YES])
                TRDie(1, @"cannot write %@", TRWithSuffix(json, suffix));
            }
          if (png)
            {
              NSData *data = TRRenderPNG(box, outlines);
              if (data == nil || ![data writeToFile: TRWithSuffix(png, suffix) atomically: YES])
                TRDie(1, @"cannot write %@", TRWithSuffix(png, suffix));
            }
          printf("%s: %gx%g, %lu lint finding(s)\n", [screen UTF8String], W, H,
                 (unsigned long)[lint count]);
          [win close];
        }
      return lintErrors ? 1 : 0;
    }
}
