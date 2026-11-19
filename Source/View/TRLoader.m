/* TRLoader.m - builds views from .trellis layout files.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRLoader.h"
#import "TRSplitView.h"
#import "TRVirtualBox.h"
#import "TRViewMeasure.h"
#import "TRAppKitCompat.h"
#import <objc/runtime.h>

static NSError *TRLoadError(TRMarkupDocument *doc, TRMarkupElement *e, NSString *fmt, ...) NS_FORMAT_FUNCTION(3,4);
static NSError *TRLoadError(TRMarkupDocument *doc, TRMarkupElement *e, NSString *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  NSString *m = [[NSString alloc] initWithFormat: fmt arguments: ap];
  va_end(ap);
  NSString *full = [NSString stringWithFormat: @"%@:%lu:%lu: %@", doc.name,
                     (unsigned long)e.line, (unsigned long)e.column, m];
  return [NSError errorWithDomain: TRMarkupErrorDomain code: 10
                         userInfo: @{NSLocalizedDescriptionKey: full}];
}

static char kTRPendingLabelFor, kTRPendingLabelForElement;

/* Every view under root, scrolled content included. */
static void TRAllViews(NSView *v, NSMutableArray *out)
{
  [out addObject: v];
  if ([v isKindOfClass: [NSScrollView class]] && [(NSScrollView *)v documentView])
    TRAllViews([(NSScrollView *)v documentView], out);
  else
    for (NSView *s in [v subviews]) TRAllViews(s, out);
}

/* Links each label-for label to its control. */
static BOOL TRResolveLabelFor(NSView *root, TRMarkupDocument *doc, NSError **error)
{
  NSMutableArray *views = [NSMutableArray array];
  TRAllViews(root, views);
  NSMutableDictionary *byId = [NSMutableDictionary dictionary];
  for (NSView *v in views) if ([v identifier]) byId[[v identifier]] = v;
  for (NSView *v in views)
    {
      NSString *target = objc_getAssociatedObject(v, &kTRPendingLabelFor);
      if (target == nil) continue;
      TRMarkupElement *e = objc_getAssociatedObject(v, &kTRPendingLabelForElement);
      objc_setAssociatedObject(v, &kTRPendingLabelFor, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      objc_setAssociatedObject(v, &kTRPendingLabelForElement, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      NSView *control = byId[target];
      if (control == nil)
        {
          if (error) *error = TRLoadError(doc, e, @"label-for=\"%@\": no element with that id", target);
          return NO;
        }
      TRSetAccessibilityTitleView(control, v);
    }
  return YES;
}

static BOOL TRYes(NSString *v)
{
  return v && ([v isEqualToString: @"yes"] || [v isEqualToString: @"true"] || [v isEqualToString: @"on"]
               || [v isEqualToString: @"1"]);
}

/* A yes/no attribute, HTML-style: bare, its own name, yes, true, on or 1
   mean yes; no, false, off or 0 mean no. Returns NO for anything else. */
static BOOL TRFlag(NSString *v, NSString *name, BOOL *on)
{
  if ([v isEqualToString: @"no"] || [v isEqualToString: @"false"] || [v isEqualToString: @"off"]
      || [v isEqualToString: @"0"])
    { *on = NO; return YES; }
  if ([v length] == 0 || TRYes(v) || [v isEqualToString: name]) { *on = YES; return YES; }
  return NO;
}

/* ------------------------------------------------------------------ */

@implementation TRScrollBox
{
  TRBoxView *_box;
  int _overlay;            /* -1 not known yet, 0 legacy, 1 overlay scrollers */
}

- (instancetype)initWithFrame:(NSRect)frame
{
  if ((self = [super initWithFrame: frame]) != nil)
    {
      _overlay = -1;
      _box = [TRBoxView boxWithStyle: @"flex-direction: column"];
      [self setHasVerticalScroller: YES];
      [self setHasHorizontalScroller: NO];
      [self setBorderType: NSNoBorder];
      [self setDrawsBackground: NO];
      [self setDocumentView: _box];
    }
  return self;
}

- (TRBoxView *)contentBox
{
  return _box;
}

- (void)layoutContent
{
  /* Container queries in the content test the container outside the
     scroller (the content box is a separate Trellis root). */
  NSView *sv = [self superview];
  if ([sv isKindOfClass: [TRBoxView class]])
    _box.node.containerQueryParent = [(TRBoxView *)sv nodeForSubview: self];
  NSSize cs = [self contentSize];
#ifdef GNUSTEP
  /* A theme with overlay scrollers (Adwaita) gives the content the full
     width and draws the scroller over it. The style is read once, while
     the scroller is still on: a scroll view without one always has the
     full width. Legacy scrollers keep their column and stay on (turning
     them off would change the content width). */
  if (_overlay < 0 && [self hasVerticalScroller] && [self frame].size.width > 0)
    _overlay = fabs(cs.width - [self frame].size.width) < 0.5 ? 1 : 0;
#endif
  [_box.node layoutWithAvailableSize: TRSizeMake(cs.width, NAN) direction: [_box inheritedLayoutDirection]];
#ifdef GNUSTEP
  /* Overlay scrollers: like AppKit's overlay style, have one only when
     there is something to scroll. -autohidesScrollers isn't enough: the
     theme still draws its inner border beside a hidden scroller, a line
     over the content's right edge. The content width doesn't change. */
  if (_overlay == 1)
    {
      BOOL needs = ceil(_box.node.layoutFrame.height) > cs.height + 0.5;
      if (needs != [self hasVerticalScroller])
        {
          CGFloat w = cs.width;
          [self setHasVerticalScroller: needs];
          cs = [self contentSize];
          if (fabs(cs.width - w) > 0.5)   /* not overlay after all: lay out again */
            [_box.node layoutWithAvailableSize: TRSizeMake(cs.width, NAN) direction: [_box inheritedLayoutDirection]];
        }
    }
#endif
  CGFloat h = MAX(ceil(_box.node.layoutFrame.height), cs.height);
  [_box setFrame: NSMakeRect(0, 0, cs.width, h)];
  [_box layoutTrellis];
}

/* GNUstep's -setFrame: does not go through -setFrameSize:, so both. */
- (void)setFrameSize:(NSSize)size
{
  [super setFrameSize: size];
  [self layoutContent];
}

- (void)setFrame:(NSRect)frame
{
  [super setFrame: frame];
  [self layoutContent];
}

@end

/* ------------------------------------------------------------------ */

@implementation TRFlatButtonCell

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view
{
  NSAttributedString *t = [self attributedTitle];
  if ([t length] == 0) return;
  if (![self isEnabled] || [self isHighlighted])
    {
      NSMutableAttributedString *m = [t mutableCopy];
      NSColor *c = [t attribute: NSForegroundColorAttributeName atIndex: 0 effectiveRange: NULL]
                   ?: [NSColor controlTextColor];
      [m addAttribute: NSForegroundColorAttributeName value: [c colorWithAlphaComponent: 0.6]
                range: NSMakeRange(0, [m length])];
      t = m;
    }
  NSSize s = [t size];
  NSRect r = NSMakeRect(NSMidX(frame) - s.width / 2, NSMidY(frame) - s.height / 2, s.width, s.height);
  /* drawAtPoint: never wraps; drawInRect: with the text's exact width
     can wrap the last word onto a clipped second line after rounding. */
  [t drawAtPoint: [view centerScanRect: r].origin];
}

- (NSSize)cellSize
{
  NSSize s = [[self attributedTitle] size];
  return NSMakeSize(ceil(s.width) + 8, ceil(s.height) + 4);
}

@end

/* ------------------------------------------------------------------ */

@interface TRPlaceholderView : TRBoxView
@end
@implementation TRPlaceholderView
@end

NSString *const TRLoaderDidReloadNotification = @"TRLoaderDidReloadNotification";

#ifndef TR_NO_HOT_RELOAD
/* A box made from a file, watched for changes while hot reload is on. */
@interface TRHotReloadEntry : NSObject
{
@public
  NSString *path;
  NSData *contents;
  __weak id owner;
}
@end
@implementation TRHotReloadEntry
@end

static NSMapTable *gWatched;          /* TRBoxView (weak) -> TRHotReloadEntry */
static NSTimer *gReloadTimer;
static int gHotReload = -1;           /* -1: not decided yet */

static BOOL TRHotReloadOn(void)
{
  if (gHotReload < 0)
    {
      NSString *env = [[[NSProcessInfo processInfo] environment] objectForKey: @"TRELLIS_HOT_RELOAD"];
      gHotReload = ([env length] && ![env isEqualToString: @"0"])
                || [[NSUserDefaults standardUserDefaults] boolForKey: @"TRHotReload"];
    }
  return gHotReload == 1;
}

@interface TRLoader (HotReloadTimer)
+ (void)_hotReloadTick:(NSTimer *)timer;
@end
#endif

@interface TRLoader (TRSampleDepth)
+ (BOOL)applySample:(NSDictionary *)sample toView:(NSView *)root depth:(int)depth error:(NSError **)error;
@end

static NSView *TRFindView(NSString *identifier, NSView *root);

/* Sample content for a <virtual>: "items" cycled up to `repeat` times
   the count. An entry {"_repeat": n, "items": [...]} expands in place to
   n rounds of its items (a group of a given size). In strings, "{i}" is
   the item's number in the whole list and "{n}" its number in its run
   (both from 1; "{n:4}" pads to 4 digits); "_template" picks the
   template. Used by trellis-render and Preview. */
@interface TRVirtualSample : NSObject <TRVirtualDataSource>
{
@public
  NSArray *items;
  NSInteger repeat;
  NSMutableArray *runs;      /* [entries, start, count] */
  NSInteger perRound;
}
@end

static char kTRVirtualSampleKey;

@implementation TRVirtualSample
- (void)buildRuns
{
  runs = [NSMutableArray array];
  NSInteger start = 0;
  for (id it in items)
    {
      NSDictionary *d = [it isKindOfClass: [NSDictionary class]] ? it : @{};
      NSArray *sub = [d[@"items"] isKindOfClass: [NSArray class]] && d[@"_repeat"] ? d[@"items"] : nil;
      NSArray *entries = sub ?: @[d];
      NSInteger count = sub ? (NSInteger)[sub count] * MAX([d[@"_repeat"] integerValue], 0) : 1;
      if (count == 0 || [entries count] == 0) continue;
      [runs addObject: @[entries, @(start), @(count)]];
      start += count;
    }
  perRound = start;
}
- (NSInteger)numberOfItemsInVirtualBox:(TRVirtualBox *)box
{
  if (runs == nil) [self buildRuns];
  return perRound * repeat;
}
- (NSDictionary *)itemAt:(NSInteger)i run:(NSInteger *)inRun
{
  if (runs == nil) [self buildRuns];
  if (perRound == 0) return @{};
  NSInteger k = i % perRound;
  for (NSArray *r in runs)
    {
      NSInteger st = [r[1] integerValue], c = [r[2] integerValue];
      if (k < st + c)
        {
          NSArray *entries = r[0];
          if (inRun) *inRun = k - st;
          return entries[(NSUInteger)(k - st) % [entries count]];
        }
    }
  return @{};
}
- (NSString *)virtualBox:(TRVirtualBox *)box templateForItemAtIndex:(NSInteger)i
{
  return [self itemAt: i run: NULL][@"_template"];
}
static NSString *TRSampleString(NSString *s, NSInteger i, NSInteger n)
{
  if ([s rangeOfString: @"{"].location == NSNotFound) return s;
  s = [s stringByReplacingOccurrencesOfString: @"{i}" withString: [NSString stringWithFormat: @"%ld", (long)(i + 1)]];
  s = [s stringByReplacingOccurrencesOfString: @"{n}" withString: [NSString stringWithFormat: @"%ld", (long)(n + 1)]];
  for (int w = 2; w <= 6; w++)
    s = [s stringByReplacingOccurrencesOfString: [NSString stringWithFormat: @"{n:%d}", w]
                                     withString: [NSString stringWithFormat: @"%0*ld", w, (long)(n + 1)]];
  return s;
}
static id TRSampleSubst(id v, NSInteger i, NSInteger n)
{
  if ([v isKindOfClass: [NSString class]]) return TRSampleString(v, i, n);
  if ([v isKindOfClass: [NSDictionary class]])
    {
      NSMutableDictionary *d = [NSMutableDictionary dictionary];
      for (id k in v) d[k] = TRSampleSubst(((NSDictionary *)v)[k], i, n);
      return d;
    }
  if ([v isKindOfClass: [NSArray class]])
    {
      NSMutableArray *a = [NSMutableArray array];
      for (id x in v) [a addObject: TRSampleSubst(x, i, n)];
      return a;
    }
  return v;
}
- (void)virtualBox:(TRVirtualBox *)box configureView:(NSView *)view atIndex:(NSInteger)i
{
  NSInteger n = 0;
  NSDictionary *it = TRSampleSubst([self itemAt: i run: &n], i, n);
  NSError *err = nil;
  if (![TRLoader applySample: it toView: view depth: 1 error: &err])
    NSLog(@"sample item %ld: %@", (long)i, [err localizedDescription]);
}
@end

/* ------------------------------------------------------------------ */
#pragma mark Rich text labels

static NSSet *TRInlineNames(void)
{
  static NSSet *set;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    set = [NSSet setWithObjects: @"b", @"strong", @"i", @"em", @"code", @"a", @"br", nil];
  });
  return set;
}

/* YES if every child (recursively) is an inline element. */
static BOOL TRAllInline(TRMarkupElement *e)
{
  for (TRMarkupElement *c in e.children)
    if (![TRInlineNames() containsObject: c.name] || !TRAllInline(c)) return NO;
  return YES;
}

/* Flattens rich content into runs {text, b, i, code, href, action},
   collapsing whitespace across run boundaries as HTML does. */
static void TRCollectRuns(TRMarkupElement *e, NSDictionary *style, NSMutableArray *runs)
{
  for (id piece in e.content)
    {
      if ([piece isKindOfClass: [NSString class]])
        {
          NSMutableDictionary *r = [style mutableCopy];
          r[@"text"] = piece;
          [runs addObject: r];
          continue;
        }
      TRMarkupElement *c = piece;
      NSMutableDictionary *st = [style mutableCopy];
      NSString *n = c.name;
      if ([n isEqualToString: @"br"]) { [runs addObject: @{@"text": @"\n", @"br": @YES}]; continue; }
      if ([n isEqualToString: @"b"] || [n isEqualToString: @"strong"]) st[@"b"] = @YES;
      if ([n isEqualToString: @"i"] || [n isEqualToString: @"em"]) st[@"i"] = @YES;
      if ([n isEqualToString: @"code"]) st[@"code"] = @YES;
      if ([n isEqualToString: @"a"])
        {
          st[@"link"] = @YES;
          if (c.attributes[@"href"]) st[@"href"] = c.attributes[@"href"];
          if (c.attributes[@"action"]) st[@"action"] = c.attributes[@"action"];
        }
      TRCollectRuns(c, st, runs);
    }
}

static NSArray *TRCollapseRuns(NSArray *runs)
{
  NSMutableArray *out = [NSMutableArray array];
  BOOL lastSpace = YES;   /* trims the start */
  NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  for (NSDictionary *r in runs)
    {
      if (r[@"br"]) { [out addObject: r]; lastSpace = YES; continue; }
      NSString *t = r[@"text"];
      NSMutableString *m = [NSMutableString string];
      for (NSUInteger i = 0; i < [t length]; i++)
        {
          unichar c = [t characterAtIndex: i];
          if ([ws characterIsMember: c]) { if (!lastSpace) [m appendString: @" "]; lastSpace = YES; }
          else { [m appendFormat: @"%C", c]; lastSpace = NO; }
        }
      if ([m length] == 0) continue;
      NSMutableDictionary *n = [r mutableCopy];
      n[@"text"] = m;
      [out addObject: n];
    }
  /* trim the end */
  while ([out count])
    {
      NSMutableDictionary *last = [[out lastObject] mutableCopy];
      NSString *t = last[@"text"];
      if (last[@"br"] == nil && [t hasSuffix: @" "])
        {
          t = [t substringToIndex: [t length] - 1];
          if ([t length] == 0) { [out removeLastObject]; continue; }
          last[@"text"] = t;
          [out replaceObjectAtIndex: [out count] - 1 withObject: last];
        }
      break;
    }
  return out;
}

static NSString *const TRRunAttributeName = @"TRRunIndex";

@implementation TRSegmentedControl

- (NSSize)trellisSizeForWidth:(CGFloat)width
{
  NSFont *f = [self font] ?: [NSFont systemFontOfSize: 0];
  NSFont *bold = [[NSFontManager sharedFontManager] convertFont: f toHaveTrait: NSBoldFontMask];
  CGFloat widest = 0;
  NSInteger n = [self segmentCount];
  for (NSInteger i = 0; i < n; i++)
    {
      NSString *l = [self labelForSegment: i] ?: @"";
      for (NSFont *font in bold ? @[f, bold] : @[f])
        widest = MAX(widest, [l sizeWithAttributes: @{NSFontAttributeName: font}].width);
    }
  NSSize cell = TRCellSize([self cell]);
  CGFloat h = MAX(cell.height, ceil([f ascender] - [f descender]) + 8);
  CGFloat w = n * (ceil(widest) + 24) + 2;
  return NSMakeSize(MAX(w, cell.width), MAX(h, 24));
}

- (NSArray<NSString *> *)selectedTitles
{
  NSMutableArray *a = [NSMutableArray array];
  for (NSInteger i = 0; i < [self segmentCount]; i++)
    if ([self isSelectedForSegment: i]) [a addObject: [self labelForSegment: i] ?: @""];
  return a;
}

- (void)setSelectedTitles:(NSArray<NSString *> *)titles
{
  for (NSInteger i = 0; i < [self segmentCount]; i++)
    [self setSelected: [titles containsObject: [self labelForSegment: i] ?: @""] forSegment: i];
}

@end

/* ------------------------------------------------------------------ */

@implementation TRRichLabel
{
  NSArray *_runs;
}

- (void)setTrellisRuns:(NSArray *)runs
{
  _runs = [runs copy];
  [self trellisRebuildRichText];
}

- (NSArray *)trellisRuns { return _runs; }

- (NSString *)plainText
{
  NSMutableString *m = [NSMutableString string];
  for (NSDictionary *r in _runs) [m appendString: r[@"text"]];
  return m;
}

/* Re-applies the runs over the label's current font, colour and
   alignment (after a style change, and when set). */
- (void)trellisRebuildRichText
{
  NSFont *base = [self font] ?: [NSFont systemFontOfSize: 0];
  NSColor *color = [self textColor] ?: [NSColor controlTextColor];
  NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
  [ps setAlignment: [self alignment]];
  [ps setLineBreakMode: [[self cell] wraps] ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail];
  NSMutableAttributedString *out = [NSMutableAttributedString new];
  NSFontManager *fm = [NSFontManager sharedFontManager];
  NSUInteger idx = 0;
  for (NSDictionary *r in _runs)
    {
      NSFont *f = base;
      if (r[@"code"])
        f = [NSFont userFixedPitchFontOfSize: [base pointSize] * 0.95] ?: base;
      if (r[@"b"]) f = [fm convertFont: f toHaveTrait: NSBoldFontMask] ?: f;
      BOOL slant = NO;
      if (r[@"i"])
        {
          NSFont *it = [fm convertFont: f toHaveTrait: NSItalicFontMask];
          if (it && ([fm traitsOfFont: it] & NSItalicFontMask)) f = it;
          else slant = YES;   /* no italic face installed: a synthetic slant */
        }
      NSMutableDictionary *attrs = [@{ NSFontAttributeName: f, NSForegroundColorAttributeName: color,
                                       NSParagraphStyleAttributeName: ps, TRRunAttributeName: @(idx) } mutableCopy];
      if (slant) attrs[NSObliquenessAttributeName] = @0.2;
      if (r[@"link"])
        {
          attrs[NSForegroundColorAttributeName] = TRColorFromCSS(@"LinkText") ?: [NSColor blueColor];
          attrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
          if (r[@"href"]) attrs[NSLinkAttributeName] = r[@"href"];
        }
      [out appendAttributedString: [[NSAttributedString alloc] initWithString: r[@"text"] attributes: attrs]];
      idx++;
    }
  [self setAttributedStringValue: out];
}

/* The layout of the text as the cell draws it (for hit testing). */
- (NSLayoutManager *)trellisLayoutWithContainer:(NSTextContainer **)tc origin:(NSPoint *)origin
{
  NSRect r = [[self cell] titleRectForBounds: [self bounds]];
  NSTextStorage *ts = [[NSTextStorage alloc] initWithAttributedString: [self attributedStringValue]];
  NSLayoutManager *lm = [NSLayoutManager new];
  NSTextContainer *c = [[NSTextContainer alloc] initWithContainerSize: NSMakeSize(NSWidth(r), 1e7)];
  [c setLineFragmentPadding: 2];
  [lm addTextContainer: c];
  [ts addLayoutManager: lm];
  [lm glyphRangeForTextContainer: c];
  if (tc) *tc = c;
  if (origin) *origin = r.origin;
  /* Keep the storage alive with the manager. */
  objc_setAssociatedObject(lm, &kTRVirtualSampleKey, ts, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  return lm;
}

- (NSUInteger)linkIndexAtPoint:(NSPoint)p
{
  NSTextContainer *c = nil;
  NSPoint o;
  NSLayoutManager *lm = [self trellisLayoutWithContainer: &c origin: &o];
  NSPoint q = NSMakePoint(p.x - o.x, [self isFlipped] ? p.y - o.y : NSMaxY([[self cell] titleRectForBounds: [self bounds]]) - p.y);
  NSRect used = [lm usedRectForTextContainer: c];
  if (!NSPointInRect(q, NSInsetRect(used, -1, -1))) return NSNotFound;
  CGFloat frac = 0;
  NSUInteger g = [lm glyphIndexForPoint: q inTextContainer: c fractionOfDistanceThroughGlyph: &frac];
  NSUInteger ci = [lm characterIndexForGlyphAtIndex: g];
  NSAttributedString *s = [self attributedStringValue];
  if (ci >= [s length]) return NSNotFound;
  NSNumber *run = [s attribute: TRRunAttributeName atIndex: ci effectiveRange: NULL];
  if (run == nil || _runs[[run unsignedIntegerValue]][@"link"] == nil) return NSNotFound;
  return ci;
}

- (NSRect)rectForLinkAtRun:(NSUInteger)runIndex
{
  NSAttributedString *s = [self attributedStringValue];
  NSRange want = NSMakeRange(NSNotFound, 0);
  for (NSUInteger i = 0; i < [s length]; )
    {
      NSRange er;
      NSNumber *run = [s attribute: TRRunAttributeName atIndex: i effectiveRange: &er];
      if ([run unsignedIntegerValue] == runIndex) { want = er; break; }
      i = NSMaxRange(er);
    }
  if (want.location == NSNotFound) return NSZeroRect;
  NSTextContainer *c = nil;
  NSPoint o;
  NSLayoutManager *lm = [self trellisLayoutWithContainer: &c origin: &o];
  NSRange gr = [lm glyphRangeForCharacterRange: want actualCharacterRange: NULL];
  NSRect r = [lm boundingRectForGlyphRange: gr inTextContainer: c];
  if ([self isFlipped]) return NSOffsetRect(r, o.x, o.y);
  NSRect title = [[self cell] titleRectForBounds: [self bounds]];
  return NSMakeRect(o.x + r.origin.x, NSMaxY(title) - NSMaxY(r), r.size.width, r.size.height);
}

- (BOOL)activateLinkAtCharacterIndex:(NSUInteger)ci
{
  NSAttributedString *s = [self attributedStringValue];
  if (ci >= [s length]) return NO;
  NSNumber *run = [s attribute: TRRunAttributeName atIndex: ci effectiveRange: NULL];
  if (run == nil) return NO;
  NSDictionary *r = _runs[[run unsignedIntegerValue]];
  if (r[@"link"] == nil) return NO;
  _clickedLink = r[@"href"];
  if (r[@"action"])
    {
      SEL sel = NSSelectorFromString(r[@"action"]);
      return [NSApp sendAction: sel to: _linkTarget from: self];
    }
  NSURL *url = r[@"href"] ? [NSURL URLWithString: r[@"href"]] : nil;
  NSString *scheme = [[url scheme] lowercaseString];
  if (url && ([scheme isEqualToString: @"https"] || [scheme isEqualToString: @"http"] || [scheme isEqualToString: @"mailto"]))
    return [[NSWorkspace sharedWorkspace] openURL: url];
  return NO;
}

- (void)mouseDown:(NSEvent *)event
{
  NSPoint p = [self convertPoint: [event locationInWindow] fromView: nil];
  NSUInteger ci = [self linkIndexAtPoint: p];
  if (ci == NSNotFound) { [super mouseDown: event]; return; }
  [self activateLinkAtCharacterIndex: ci];
}

- (void)resetCursorRects
{
  [super resetCursorRects];
  for (NSUInteger i = 0; i < [_runs count]; i++)
    if (_runs[i][@"link"])
      {
        NSRect r = [self rectForLinkAtRun: i];
        if (!NSIsEmptyRect(r)) [self addCursorRect: r cursor: [NSCursor pointingHandCursor]];
      }
}

@end

@implementation TRLoader

static NSTextField *TRMakeLabel(NSString *text, BOOL wraps)
{
  NSTextField *f = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
  [f setStringValue: text ?: @""];
  [f setEditable: NO];
  [f setSelectable: NO];
  [f setBezeled: NO];
  [f setBordered: NO];
  [f setDrawsBackground: NO];
  /* Explicit either way: GNUstep text-field cells wrap by default, Apple's
     do not. Labels are single-line unless asked; lint flags clipping. */
  [[f cell] setWraps: wraps];
  [[f cell] setLineBreakMode: wraps ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail];
  return f;
}

/* Builds the view for one element (and its subtree). */
+ (NSView *)viewForElement:(TRMarkupElement *)e document:(TRMarkupDocument *)doc
                     owner:(id)owner error:(NSError **)error
{
  NSString *n = e.name;
  NSDictionary *a = e.attributes;
  NSString *text = [e text];
  NSView *v = nil;
  BOOL container = NO;

  if ([n isEqualToString: @"column"] || [n isEqualToString: @"row"] || [n isEqualToString: @"box"])
    {
      v = [[TRBoxView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
      container = YES;
    }
  else if ([n isEqualToString: @"scroll"])
    v = [[TRScrollBox alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
  else if ([n isEqualToString: @"virtual"])
    {
      NSString *layout = a[@"layout"] ?: @"list";
      if (![layout isEqualToString: @"list"] && ![layout isEqualToString: @"grid"])
        {
          if (error) *error = TRLoadError(doc, e, @"<virtual layout=\"%@\">: use list or grid", layout);
          return nil;
        }
      TRVirtualBox *vb = [[TRVirtualBox alloc] initWithMode: [layout isEqualToString: @"grid"]
                                                          ? TRVirtualModeGrid : TRVirtualModeList];
      for (TRMarkupElement *c in e.children)
        {
          if (![c.name isEqualToString: @"template"] || c.attributes[@"id"] == nil || [c.children count] != 1)
            {
              if (error) *error = TRLoadError(doc, c, @"<virtual> may only contain <template id=\"...\"> elements with one child each");
              return nil;
            }
          [vb registerTemplateElement: c ofDocument: doc];
        }
      if (a[@"template"]) vb.defaultTemplate = a[@"template"];
      else if ([e.children count]) vb.defaultTemplate = ((TRMarkupElement *)e.children[0]).attributes[@"id"];
      if (a[@"estimated-size"]) vb.estimatedSize = [a[@"estimated-size"] doubleValue];
      if (a[@"overscan"]) vb.overscan = [a[@"overscan"] doubleValue];
      NSMutableArray *base = [NSMutableArray array];
      for (TRMatchedDeclarations *m in [doc declarationsForElement: e])
        if (m.condition == nil) [base addObject: m.declarations];
      NSError *err = nil;
      if (![vb setContainerDeclarations: [base componentsJoinedByString: @"; "] error: &err])
        {
          if (error) *error = TRLoadError(doc, e, @"%@", [err localizedDescription]);
          return nil;
        }
      v = vb;
    }
  else if ([n isEqualToString: @"split"])
    {
      NSString *dir = a[@"direction"] ?: @"row";
      if (![dir isEqualToString: @"row"] && ![dir isEqualToString: @"column"])
        {
          if (error) *error = TRLoadError(doc, e, @"<split direction=\"%@\">: use row or column", dir);
          return nil;
        }
      if ([e.children count] == 0)
        {
          if (error) *error = TRLoadError(doc, e, @"<split> has no panes");
          return nil;
        }
      TRSplitView *sv = [[TRSplitView alloc] initWithDirection: [dir isEqualToString: @"column"]
                                                                ? TRSplitDirectionColumn : TRSplitDirectionRow];
      NSString *divider = a[@"divider"];
      if (divider)
        {
          if ([divider isEqualToString: @"thin"]) [sv setDividerStyle: NSSplitViewDividerStyleThin];
          else if ([divider isEqualToString: @"thick"]) [sv setDividerStyle: NSSplitViewDividerStyleThick];
          else if ([divider isEqualToString: @"pane"]) [sv setDividerStyle: NSSplitViewDividerStylePaneSplitter];
          else
            {
              if (error) *error = TRLoadError(doc, e, @"<split divider=\"%@\">: use thin, thick or pane", divider);
              return nil;
            }
        }
      for (TRMarkupElement *c in e.children)
        {
          NSView *pv = [self viewForElement: c document: doc owner: owner error: error];
          if (pv == nil) return nil;
          [sv addPane: pv];
          NSString *h = c.attributes[@"hidden"];
          BOOL hidePane = NO;
          if (h && !TRFlag(h, @"hidden", &hidePane))
            {
              if (error) *error = TRLoadError(doc, c, @"hidden=\"%@\": use yes or no", h);
              return nil;
            }
          /* The pane's sizing declarations go to the split; the rest style
             the pane itself, which the split sizes. */
          NSMutableArray *base = [NSMutableArray array];
          NSArray *matched = [doc declarationsForElement: c];
          for (TRMatchedDeclarations *m in matched)
            if (m.condition == nil) [base addObject: m.declarations];
          NSString *joined = [base componentsJoinedByString: @"; "];
          TRStyle *st = [TRStyle new];
          NSError *err = nil;
          if (![st applyDeclarations: joined error: &err])
            {
              if (error) *error = TRLoadError(doc, c, @"%@", [err localizedDescription]);
              return nil;
            }
          [sv setSizingFromStyle: st forPane: pv];
          if ([pv isKindOfClass: [TRBoxView class]])
            {
              TRBoxView *pb = (TRBoxView *)pv;
              @try { [pb setStyleDeclarations: joined]; }
              @catch (NSException *x)
                {
                  if (error) *error = TRLoadError(doc, c, @"%@", [x reason]);
                  return nil;
                }
              TRStyle *own = pb.style;
              own.width = TRAuto; own.height = TRAuto; own.flexBasis = TRAuto;
              own.minWidth = TRAuto; own.minHeight = TRAuto;
              own.maxWidth = TRNoneValue(); own.maxHeight = TRNoneValue();
              pb.style = own;
              for (TRMatchedDeclarations *m in matched)
                if (m.condition != nil) [pb addConditionalStyle: m.declarations when: m.condition];
            }
          else
            TRApplyLeafStyle(pv, joined);
          if (hidePane) [sv setHidden: YES forPane: pv];
        }
      if (a[@"autosave"]) sv.autosave = a[@"autosave"];
      v = sv;
    }
  else if ([n isEqualToString: @"label"])
    v = TRMakeLabel(a[@"text"] ?: text, TRYes(a[@"wraps"]));
  else if ([n isEqualToString: @"text"])
    v = TRMakeLabel(a[@"text"] ?: text, YES);
  else if ([n isEqualToString: @"field"])
    {
      NSTextField *f = TRYes(a[@"secure"]) ? [[NSSecureTextField alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)]
                                          : [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
      [f setStringValue: a[@"value"] ?: text ?: @""];
      [[f cell] setWraps: NO];
      [[f cell] setScrollable: YES];
      if (a[@"placeholder"]) [[f cell] setPlaceholderString: a[@"placeholder"]];
      if (a[@"editable"] && !TRYes(a[@"editable"])) [f setEditable: NO];
      v = f;
    }
  else if ([n isEqualToString: @"button"] || [n isEqualToString: @"checkbox"] || [n isEqualToString: @"radio"])
    {
      NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
      BOOL flat = [n isEqualToString: @"button"] && a[@"bordered"] != nil && !TRYes(a[@"bordered"]);
      /* bordered="no": a flat, title-only button (chips on a bar). Its cell
         draws the title itself, so a color: set on it shows even under
         themes that draw push-button titles in their own colour. */
      if (flat) [b setCell: [[TRFlatButtonCell alloc] initTextCell: @""]];
      if ([n isEqualToString: @"checkbox"]) [b setButtonType: NSButtonTypeSwitch];
      else if ([n isEqualToString: @"radio"]) [b setButtonType: NSButtonTypeRadio];
      else if (!flat) [b setBezelStyle: NSBezelStyleRounded];
      if (flat) [b setBordered: NO];
      [b setTitle: a[@"title"] ?: text ?: @""];
      if (a[@"state"]) [b setState: TRYes(a[@"state"]) ? NSControlStateValueOn : NSControlStateValueOff];
      if (TRYes(a[@"default"])) [b setKeyEquivalent: @"\r"];
      v = b;
    }
  else if ([n isEqualToString: @"popup"])
    {
      NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 10, 10) pullsDown: NO];
      for (TRMarkupElement *c in e.children)
        {
          if (![c.name isEqualToString: @"item"])
            {
              if (error) *error = TRLoadError(doc, c, @"<popup> may only contain <item> elements, not <%@>", c.name);
              return nil;
            }
          [p addItemWithTitle: c.attributes[@"title"] ?: [c text]];
        }
      if (a[@"items"])
        for (NSString *t in [a[@"items"] componentsSeparatedByString: @","])
          [p addItemWithTitle: [t stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]]];
      if (a[@"selected"]) [p selectItemWithTitle: a[@"selected"]];
      v = p;
    }
  else if ([n isEqualToString: @"segmented"])
    {
      NSMutableArray *titles = [NSMutableArray array];
      NSMutableIndexSet *chosen = [NSMutableIndexSet indexSet];
      for (TRMarkupElement *c in e.children)
        {
          if (![c.name isEqualToString: @"item"])
            {
              if (error) *error = TRLoadError(doc, c, @"<segmented> may only contain <item> elements, not <%@>", c.name);
              return nil;
            }
          if (TRYes(c.attributes[@"selected"])) [chosen addIndex: [titles count]];
          [titles addObject: c.attributes[@"title"] ?: [c text] ?: @""];
        }
      if (a[@"items"])
        for (NSString *t in [a[@"items"] componentsSeparatedByString: @","])
          [titles addObject: [t stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]]];
      if ([titles count] == 0)
        {
          if (error) *error = TRLoadError(doc, e, @"<segmented> has no items (use <item> children or items=\"A, B\")");
          return nil;
        }
      NSString *tracking = a[@"tracking"] ?: @"one";
      NSSegmentSwitchTracking mode;
      if ([tracking isEqualToString: @"one"]) mode = NSSegmentSwitchTrackingSelectOne;
      else if ([tracking isEqualToString: @"any"]) mode = NSSegmentSwitchTrackingSelectAny;
      else if ([tracking isEqualToString: @"momentary"]) mode = NSSegmentSwitchTrackingMomentary;
      else
        {
          if (error) *error = TRLoadError(doc, e, @"<segmented tracking=\"%@\">: use one, any or momentary", tracking);
          return nil;
        }
      if (a[@"selected"])
        {
          NSUInteger i = [titles indexOfObject: a[@"selected"]];
          if (i == NSNotFound)
            {
              if (error) *error = TRLoadError(doc, e, @"<segmented selected=\"%@\">: no item has that title", a[@"selected"]);
              return nil;
            }
          [chosen addIndex: i];
        }
      if (mode == NSSegmentSwitchTrackingMomentary && [chosen count])
        {
          /* AppKit never keeps a selection on a momentary control. */
          if (error) *error = TRLoadError(doc, e, @"<segmented tracking=\"momentary\"> has no selection; drop selected");
          return nil;
        }
      if (mode == NSSegmentSwitchTrackingSelectOne && [chosen count] > 1)
        {
          if (error) *error = TRLoadError(doc, e, @"<segmented tracking=\"one\"> can select only one item");
          return nil;
        }
      TRSegmentedControl *sc = [[TRSegmentedControl alloc] initWithFrame: NSMakeRect(0, 0, 100, 24)];
      [sc setSegmentCount: [titles count]];
      [[sc cell] setTrackingMode: mode];
      for (NSUInteger i = 0; i < [titles count]; i++)
        {
          [sc setLabel: titles[i] forSegment: i];
          [sc setWidth: 0 forSegment: i];   /* size to the label */
        }
      for (NSUInteger i = [chosen firstIndex]; i != NSNotFound; i = [chosen indexGreaterThanIndex: i])
        [sc setSelected: YES forSegment: i];
      v = sc;
    }
  else if ([n isEqualToString: @"image"])
    {
      NSImageView *iv = [[NSImageView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
      NSImage *img = nil;
      if (a[@"src"])
        {
          NSString *path = a[@"src"];
          if (![path isAbsolutePath])
            path = [[doc.name stringByDeletingLastPathComponent] stringByAppendingPathComponent: path];
          img = [[NSImage alloc] initWithContentsOfFile: path];
        }
      else if (a[@"name"])
        img = [NSImage imageNamed: a[@"name"]];
      [iv setImage: img];
      [iv setImageScaling: NSImageScaleProportionallyUpOrDown];
      v = iv;
    }
  else if ([n isEqualToString: @"slider"])
    {
      NSSlider *s = [[NSSlider alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)];
      if (a[@"min"]) [s setMinValue: [a[@"min"] doubleValue]];
      if (a[@"max"]) [s setMaxValue: [a[@"max"] doubleValue]];
      if (a[@"value"]) [s setDoubleValue: [a[@"value"] doubleValue]];
      v = s;
    }
  else if ([n isEqualToString: @"progress"])
    {
      NSProgressIndicator *p = [[NSProgressIndicator alloc] initWithFrame: NSMakeRect(0, 0, 100, 16)];
      [p setIndeterminate: TRYes(a[@"indeterminate"])];
      if (a[@"max"]) [p setMaxValue: [a[@"max"] doubleValue]];
      if (a[@"value"]) [p setDoubleValue: [a[@"value"] doubleValue]];
      v = p;
    }
  else if ([n isEqualToString: @"separator"])
    {
      NSBox *b = [[NSBox alloc] initWithFrame: NSMakeRect(0, 0, 100, 1)];
      [b setBoxType: NSBoxSeparator];
      [b setTitlePosition: NSNoTitle];
      v = b;
    }
  else if ([n isEqualToString: @"spacer"])
    v = [[NSView alloc] initWithFrame: NSZeroRect];
  else if ([n isEqualToString: @"view"])
    {
      NSString *type = a[@"type"];
      Class cls = type ? NSClassFromString(type) : Nil;
      if (cls && [cls isSubclassOfClass: [NSView class]])
        v = [[cls alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
      else
        {
          TRPlaceholderView *ph = [TRPlaceholderView boxWithStyle:
            @"min-height: 40px; min-width: 80px; align-items: center; justify-content: center; "
            @"background-color: #efe6f7; border: 1px solid #a68bc4"];
          [ph addSubview: TRMakeLabel(type ?: @"view", NO) style: @"color: #6a4c93"];
          v = ph;
        }
    }
  else
    {
      if (error) *error = TRLoadError(doc, e, @"unknown element <%@>", n);
      return nil;
    }

  if (([n isEqualToString: @"label"] || [n isEqualToString: @"text"]) && [e.children count] && TRAllInline(e))
    {
      /* Rich text: <b>, <i>, <code>, <a action= href=>, <br>. */
      NSMutableArray *runs = [NSMutableArray array];
      TRCollectRuns(e, @{}, runs);
      BOOL wraps = [n isEqualToString: @"text"] || TRYes(a[@"wraps"]);
      TRRichLabel *rl = [[TRRichLabel alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
      [rl setEditable: NO];
      [rl setSelectable: NO];
      [rl setBezeled: NO];
      [rl setBordered: NO];
      [rl setDrawsBackground: NO];
      [[rl cell] setWraps: wraps];
      [[rl cell] setLineBreakMode: wraps ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail];
      rl.linkTarget = owner;
      for (NSDictionary *r in runs)
        if (r[@"action"] && owner != nil && ![owner respondsToSelector: NSSelectorFromString(r[@"action"])])
          {
            if (error) *error = TRLoadError(doc, e, @"<a action=\"%@\">: %@ does not implement -%@",
                                            r[@"action"], NSStringFromClass([owner class]), r[@"action"]);
            return nil;
          }
      [rl setTrellisRuns: TRCollapseRuns(runs)];
      v = rl;
      container = NO;
    }

  if (!container && ![n isEqualToString: @"popup"] && ![n isEqualToString: @"segmented"]
      && ![n isEqualToString: @"scroll"]
      && ![n isEqualToString: @"virtual"] && ![n isEqualToString: @"split"]
      && ![v isKindOfClass: [TRRichLabel class]] && [e.children count])
    {
      if (error) *error = TRLoadError(doc, e.children[0], @"<%@> cannot contain elements", n);
      return nil;
    }

  NSString *ident = [e identifier];
  if (ident) [v setIdentifier: ident];
  if (a[@"tabindex"]) TRSetTabIndex(v, [a[@"tabindex"] integerValue]);

  /* Accessibility. label-for is resolved once the whole tree exists. */
  if (a[@"a11y-label"]) TRSetAccessibilityLabel(v, a[@"a11y-label"]);
  NSString *role = a[@"role"];
  if (role)
    {
      if (![role isEqualToString: @"group"] && ![role isEqualToString: @"none"])
        {
          if (error) *error = TRLoadError(doc, e, @"role \"%@\" is not supported (use group or none)", role);
          return nil;
        }
      TRSetAccessibilityRole(v, role);
    }
  if (a[@"label-for"])
    {
      objc_setAssociatedObject(v, &kTRPendingLabelFor, a[@"label-for"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      objc_setAssociatedObject(v, &kTRPendingLabelForElement, e, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

  /* Action. */
  NSString *action = a[@"action"];
  if (action)
    {
      if (![v isKindOfClass: [NSControl class]])
        {
          if (error) *error = TRLoadError(doc, e, @"<%@> does not send actions", n);
          return nil;
        }
      SEL sel = NSSelectorFromString(action);
      if (owner != nil && ![owner respondsToSelector: sel])
        {
          if (error) *error = TRLoadError(doc, e, @"action '%@': %@ does not implement -%@",
                                          action, NSStringFromClass([owner class]), action);
          return nil;
        }
      [(NSControl *)v setTarget: owner];
      [(NSControl *)v setAction: sel];
    }

  /* Outlet. */
  if (ident && owner != nil)
    {
      NSString *setter = [NSString stringWithFormat: @"set%@%@:", [[ident substringToIndex: 1] uppercaseString],
                                                     [ident substringFromIndex: 1]];
      BOOL hasIvar = class_getInstanceVariable([owner class], [ident UTF8String]) != NULL
        || class_getInstanceVariable([owner class], [[@"_" stringByAppendingString: ident] UTF8String]) != NULL;
      if ([owner respondsToSelector: NSSelectorFromString(setter)] || hasIvar)
        [owner setValue: v forKey: ident];
      else if (!TRYes(a[@"no-outlet"]))
        {
          if (error) *error = TRLoadError(doc, e, @"id '%@': %@ has no outlet named '%@' (add a property, or no-outlet=\"yes\")",
                                          ident, NSStringFromClass([owner class]), ident);
          return nil;
        }
    }

  /* Children. */
  TRBoxView *box = container ? (TRBoxView *)v
                 : ([v isKindOfClass: [TRScrollBox class]] ? [(TRScrollBox *)v contentBox] : nil);
  if (box)
    for (TRMarkupElement *c in e.children)
      {
        NSView *cv = [self viewForElement: c document: doc owner: owner error: error];
        if (cv == nil) return nil;
        [box addSubview: cv];
        NSString *h = c.attributes[@"hidden"];
        if (h)
          {
            /* HTML-style: a bare hidden (or hidden="hidden") hides too. */
            BOOL hide = NO;
            if (!TRFlag(h, @"hidden", &hide))
              {
                if (error) *error = TRLoadError(doc, c, @"hidden=\"%@\": use yes or no", h);
                return nil;
              }
            [box setHidden: hide forSubview: cv];
          }
        if (![self applyStylesOf: c toView: cv inBox: box document: doc error: error]) return nil;
      }
  /* disabled: a control, or every control inside a container (like an
     HTML fieldset), after the children exist. */
  NSString *dis = a[@"disabled"];
  if (dis)
    {
      BOOL off = NO;
      if (!TRFlag(dis, @"disabled", &off))
        {
          if (error) *error = TRLoadError(doc, e, @"disabled=\"%@\": use yes or no", dis);
          return nil;
        }
      if (off) TRSetEnabled(v, NO);
    }
  return v;
}

+ (BOOL)applyStylesOf:(TRMarkupElement *)e toView:(NSView *)v inBox:(TRBoxView *)box
             document:(TRMarkupDocument *)doc error:(NSError **)error
{
  NSMutableArray *base = [NSMutableArray array];
  NSArray *matched = [doc declarationsForElement: e];
  for (TRMatchedDeclarations *m in matched)
    if (m.condition == nil) [base addObject: m.declarations];
  @try
    {
      NSString *joined = [base componentsJoinedByString: @"; "];
      if (box == nil)
        [(TRBoxView *)v setStyleDeclarations: joined];
      else
        [box setStyleDeclarations: joined forSubview: v];
      for (TRMatchedDeclarations *m in matched)
        {
          if (m.condition == nil) continue;
          if (box == nil) [(TRBoxView *)v addConditionalStyle: m.declarations when: m.condition];
          else [box addConditionalStyle: m.declarations when: m.condition forSubview: v];
        }
    }
  @catch (NSException *ex)
    {
      if (error) *error = TRLoadError(doc, e, @"%@", [ex reason]);
      return NO;
    }
  return YES;
}

+ (TRBoxView *)loadFile:(NSString *)path owner:(id)owner error:(NSError **)error
{
  TRMarkupDocument *doc = [TRMarkupDocument documentWithContentsOfFile: path error: error];
  if (doc == nil) return nil;
  TRBoxView *box = [self loadDocument: doc owner: owner error: error];
#ifndef TR_NO_HOT_RELOAD
  if (box != nil && TRHotReloadOn())
    {
      if (gWatched == nil) gWatched = [NSMapTable weakToStrongObjectsMapTable];
      TRHotReloadEntry *en = [TRHotReloadEntry new];
      en->path = [path copy];
      en->contents = [NSData dataWithContentsOfFile: path];
      en->owner = owner;
      [gWatched setObject: en forKey: box];
      [self setHotReloadEnabled: YES];   /* starts the timer */
    }
#endif
  return box;
}

#ifndef TR_NO_HOT_RELOAD
+ (void)setHotReloadEnabled:(BOOL)enabled
{
  gHotReload = enabled ? 1 : 0;
  if (enabled && gReloadTimer == nil)
    {
      gReloadTimer = [NSTimer timerWithTimeInterval: 0.5 target: self
                                           selector: @selector(_hotReloadTick:)
                                           userInfo: nil repeats: YES];
      [[NSRunLoop currentRunLoop] addTimer: gReloadTimer forMode: NSDefaultRunLoopMode];
      [[NSRunLoop currentRunLoop] addTimer: gReloadTimer forMode: NSModalPanelRunLoopMode];
      [[NSRunLoop currentRunLoop] addTimer: gReloadTimer forMode: NSEventTrackingRunLoopMode];
    }
  else if (!enabled)
    {
      [gReloadTimer invalidate];
      gReloadTimer = nil;
    }
}

+ (BOOL)hotReloadEnabled { return TRHotReloadOn(); }

+ (void)_hotReloadTick:(NSTimer *)timer
{
  (void)timer;
  [self reloadChangedFiles];
}

+ (NSUInteger)reloadChangedFiles
{
  if (!TRHotReloadOn() || gWatched == nil) return 0;
  NSUInteger n = 0;
  for (TRBoxView *old in [[gWatched keyEnumerator] allObjects])
    {
      TRHotReloadEntry *en = [gWatched objectForKey: old];
      NSData *now = [NSData dataWithContentsOfFile: en->path];
      if (now == nil || [now isEqualToData: en->contents]) continue;
      en->contents = now;
      NSView *sv = [old superview];
      if ([sv isKindOfClass: [TRBoxView class]])
        {
          fprintf(stderr, "trellis hot reload: %s: can't replace a box nested in another Trellis box\n",
                  [en->path UTF8String]);
          continue;
        }
      NSError *err = nil;
      id owner = en->owner;
      TRMarkupDocument *doc = [TRMarkupDocument documentWithContentsOfFile: en->path error: &err];
      TRBoxView *box = doc ? [self loadDocument: doc owner: owner error: &err] : nil;
      if (box == nil)
        {
          fprintf(stderr, "trellis hot reload: %s (keeping the old layout)\n", [[err localizedDescription] UTF8String]);
          continue;
        }
      NSWindow *win = [old window];
      if (win != nil && [win contentView] == old)
        [win setContentView: box];
      else if (sv != nil)
        {
          [box setFrame: [old frame]];
          [box setAutoresizingMask: [old autoresizingMask]];
          [sv replaceSubview: old with: box];
        }
      else
        [box setFrame: [old frame]];
      [box layoutTrellis];
      [gWatched removeObjectForKey: old];
      [gWatched setObject: en forKey: box];
      if ([owner respondsToSelector: @selector(trellisDidReload:)]) [owner trellisDidReload: box];
      [[NSNotificationCenter defaultCenter] postNotificationName: TRLoaderDidReloadNotification
                                                          object: box
                                                        userInfo: @{@"oldBox": old, @"path": en->path}];
      n++;
    }
  return n;
}
#else
+ (void)setHotReloadEnabled:(BOOL)enabled { (void)enabled; }
+ (BOOL)hotReloadEnabled { return NO; }
+ (NSUInteger)reloadChangedFiles { return 0; }
#endif

/* The built-in tokens' metrics from the running theme (fonts, control
   and field heights, scroller width), refreshed at each load. */
static NSString *TRPxString(CGFloat v)
{
  return [NSString stringWithFormat: @"%gpx", round(v * 2) / 2];
}

void TRUpdateThemeTokens(void)
{
  NSMutableDictionary *t = [[TRMarkupDocument defaultBuiltinCustomProperties] mutableCopy];
  t[@"--tr-font-size"] = TRPxString([NSFont systemFontSize]);
  t[@"--tr-small-font-size"] = TRPxString([NSFont smallSystemFontSize]);
  t[@"--tr-label-font-size"] = TRPxString([NSFont labelFontSize]);
  t[@"--tr-title-font-size"] = TRPxString(round([NSFont systemFontSize] * 1.3));
  NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 20)];
  [b setBezelStyle: NSBezelStyleRounded];
  [b setTitle: @"Ag"];
  t[@"--tr-control-height"] = TRPxString(ceil(TRCellSize([b cell]).height));
  NSTextField *f = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 80, 20)];
  [f setStringValue: @"Ag"];
  t[@"--tr-field-height"] = TRPxString(ceil(TRCellSize([f cell]).height));
  CGFloat sw = 15;
#ifdef GNUSTEP
  sw = [NSScroller scrollerWidth];
#else
  sw = [NSScroller scrollerWidthForControlSize: NSControlSizeRegular scrollerStyle: [NSScroller preferredScrollerStyle]];
#endif
  t[@"--tr-scroller-width"] = TRPxString(sw);
  [TRMarkupDocument setBuiltinCustomProperties: t];
}

+ (TRBoxView *)loadDocument:(TRMarkupDocument *)doc owner:(id)owner error:(NSError **)error
{
  TRUpdateThemeTokens();
  TRMarkupElement *root = doc.root;
  if (![@[@"column", @"row", @"box"] containsObject: root.name])
    {
      if (error) *error = TRLoadError(doc, root, @"the root element must be <column>, <row> or <box>, not <%@>", root.name);
      return nil;
    }
  NSView *v = [self viewForElement: root document: doc owner: owner error: error];
  if (v == nil) return nil;
  if (![self applyStylesOf: root toView: v inBox: nil document: doc error: error]) return nil;
  if (!TRResolveLabelFor(v, doc, error)) return nil;
  return (TRBoxView *)v;
}

+ (NSView *)instantiateTemplate:(NSString *)templateId ofDocument:(TRMarkupDocument *)doc
                          owner:(id)owner error:(NSError **)error
{
  TRMarkupElement *t = doc.templates[templateId];
  if (t == nil || [t.children count] != 1)
    {
      if (error) *error = [NSError errorWithDomain: TRMarkupErrorDomain code: 11 userInfo: @{
        NSLocalizedDescriptionKey: [NSString stringWithFormat: @"%@: no <template id=\"%@\"> with exactly one child",
                                     doc.name, templateId]}];
      return nil;
    }
  (void)owner;
  return [self instantiateTemplateElement: t ofDocument: doc error: error];
}

/* A copy of a <template> element's one child (top-level, or inside a
   <virtual>). Template instances are not outlets of the owner. */
+ (NSView *)instantiateTemplateElement:(TRMarkupElement *)t ofDocument:(TRMarkupDocument *)doc
                                 error:(NSError **)error
{
  TRMarkupElement *e = t.children[0];
  NSView *v = [self viewForElement: e document: doc owner: nil error: error];
  if (v == nil) return nil;
  if ([v isKindOfClass: [TRBoxView class]])
    {
      if (![self applyStylesOf: e toView: v inBox: nil document: doc error: error]) return nil;
    }
  else
    {
      /* A control as the template's root: no box styles it, so here. */
      NSMutableArray *base = [NSMutableArray array];
      for (TRMatchedDeclarations *m in [doc declarationsForElement: e])
        if (m.condition == nil) [base addObject: m.declarations];
      TRApplyLeafStyle(v, [base componentsJoinedByString: @"; "]);
    }
  if (!TRResolveLabelFor(v, doc, error)) return nil;
  return v;
}

+ (NSView *)viewWithIdentifier:(NSString *)identifier inView:(NSView *)root
{
  return TRFindView(identifier, root);
}

static NSView *TRFindView(NSString *identifier, NSView *root)
{
  if ([[root identifier] isEqualToString: identifier]) return root;
  NSArray *subs;
  if ([root isKindOfClass: [TRVirtualBox class]]) subs = @[];
  else if ([root isKindOfClass: [NSScrollView class]])
    {
      /* A scroll view may have no document view (a custom NSScrollView). */
      NSView *doc = [(NSScrollView *)root documentView];
      subs = doc ? @[doc] : @[];
    }
  else subs = [root subviews];
  for (NSView *s in subs)
    {
      NSView *f = TRFindView(identifier, s);
      if (f) return f;
    }
  return nil;
}

+ (BOOL)applySample:(NSDictionary *)sample toView:(NSView *)root error:(NSError **)error
{
  return [self applySample: sample toView: root depth: 0 error: error];
}

+ (BOOL)applySample:(NSDictionary *)sample toView:(NSView *)root depth:(int)depth error:(NSError **)error
{
  for (NSString *ident in sample)
    {
      if ([ident hasPrefix: @"_"]) continue;   /* comments / metadata */
      NSView *v = [self viewWithIdentifier: ident inView: root];
      if (v == nil)
        {
          if (error) *error = [NSError errorWithDomain: TRMarkupErrorDomain code: 12 userInfo: @{
            NSLocalizedDescriptionKey: [NSString stringWithFormat: @"sample: no view with id '%@'", ident]}];
          return NO;
        }
      id val = sample[ident];
      NSDictionary *d = [val isKindOfClass: [NSDictionary class]] ? val : nil;
      if ([v isKindOfClass: [TRVirtualBox class]])
        {
          if (depth > 0 || ![d[@"items"] isKindOfClass: [NSArray class]])
            {
              if (error) *error = [NSError errorWithDomain: TRMarkupErrorDomain code: 12 userInfo: @{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                  @"sample: '%@' is a <virtual>; give {\"items\": [...], \"repeat\": n}", ident]}];
              return NO;
            }
          TRVirtualSample *src = [TRVirtualSample new];
          src->items = d[@"items"];
          src->repeat = MAX([d[@"repeat"] integerValue], 1);
          /* The box holds its data source weakly; the sample lives with it. */
          objc_setAssociatedObject(v, &kTRVirtualSampleKey, src, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
          [(TRVirtualBox *)v setDataSource: src];
          if (d[@"scroll-to"]) [(TRVirtualBox *)v scrollToItemAtIndex: [d[@"scroll-to"] integerValue]
                                                             position: TRVirtualScrollTop];
          continue;
        }
      NSString *str = [val isKindOfClass: [NSString class]] ? val : d[@"string"];
      if ([v isKindOfClass: [NSPopUpButton class]])
        {
          NSArray *items = [val isKindOfClass: [NSArray class]] ? val : d[@"items"];
          if (items) { [(NSPopUpButton *)v removeAllItems]; [(NSPopUpButton *)v addItemsWithTitles: items]; }
          if (d[@"selected"]) [(NSPopUpButton *)v selectItemWithTitle: d[@"selected"]];
        }
      else if ([v isKindOfClass: [TRSegmentedControl class]])
        {
          id sel = d[@"selected"] ?: str;
          if ([sel isKindOfClass: [NSString class]]) sel = @[sel];
          if ([sel isKindOfClass: [NSArray class]]) [(TRSegmentedControl *)v setSelectedTitles: sel];
        }
      else if ([v isKindOfClass: [NSButton class]])
        {
          NSString *title = d[@"title"] ?: str;
          if (title) [(NSButton *)v setTitle: title];
          if (d[@"state"]) [(NSButton *)v setState: [d[@"state"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
        }
      else if ([v isKindOfClass: [NSControl class]])
        {
          if (str) [(NSControl *)v setStringValue: str];
          if (d[@"value"]) [(NSControl *)v setDoubleValue: [d[@"value"] doubleValue]];
        }
      else if ([v isKindOfClass: [NSProgressIndicator class]] && d[@"value"])
        [(NSProgressIndicator *)v setDoubleValue: [d[@"value"] doubleValue]];
      if (d[@"disabled"]) TRSetEnabled(v, ![d[@"disabled"] boolValue]);
      if (d[@"hidden"])
        {
          if ([[v superview] isKindOfClass: [TRBoxView class]])
            [(TRBoxView *)[v superview] setHidden: [d[@"hidden"] boolValue] forSubview: v];
          else if ([[v superview] isKindOfClass: [TRSplitView class]])
            [(TRSplitView *)[v superview] setHidden: [d[@"hidden"] boolValue] forPane: v];
          else
            [v setHidden: [d[@"hidden"] boolValue]];
        }
    }
  return YES;
}

@end
