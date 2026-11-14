/* TRBoxView.m - an NSView container laid out by Trellis.

   Only public AppKit API is used, so this builds unchanged on GNUstep and
   on macOS.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRBoxView.h"
#import "TRViewMeasure.h"

/* ------------------------------------------------------------------ */
#pragma mark Colours

static CGFloat TRHex(NSString *s, NSUInteger i, NSUInteger len)
{
  unsigned v = 0;
  [[NSScanner scannerWithString: [s substringWithRange: NSMakeRange(i, len)]] scanHexInt: &v];
  return len == 1 ? (v * 17) / 255.0 : v / 255.0;
}

NSColor *TRColorFromCSS(NSString *css)
{
  NSString *c = [[css stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]] lowercaseString];
  if ([c hasPrefix: @"#"])
    {
      NSString *h = [c substringFromIndex: 1];
      NSUInteger n = [h length];
      if (n == 3 || n == 4)
        return [NSColor colorWithCalibratedRed: TRHex(h, 0, 1) green: TRHex(h, 1, 1)
                                          blue: TRHex(h, 2, 1) alpha: n == 4 ? TRHex(h, 3, 1) : 1];
      if (n == 6 || n == 8)
        return [NSColor colorWithCalibratedRed: TRHex(h, 0, 2) green: TRHex(h, 2, 2)
                                          blue: TRHex(h, 4, 2) alpha: n == 8 ? TRHex(h, 6, 2) : 1];
      return nil;
    }
  if ([c hasPrefix: @"rgb"])
    {
      NSRange open = [c rangeOfString: @"("], close = [c rangeOfString: @")"];
      if (open.location == NSNotFound || close.location == NSNotFound) return nil;
      NSString *inner = [c substringWithRange: NSMakeRange(NSMaxRange(open), close.location - NSMaxRange(open))];
      inner = [inner stringByReplacingOccurrencesOfString: @"/" withString: @","];
      NSMutableArray *parts = [NSMutableArray array];
      for (NSString *p in [inner componentsSeparatedByCharactersInSet:
                             [NSCharacterSet characterSetWithCharactersInString: @", "]])
        if ([p length]) [parts addObject: p];
      if ([parts count] < 3) return nil;
      CGFloat a = [parts count] > 3 ? [parts[3] doubleValue] : 1;
      if ([parts count] > 3 && [parts[3] hasSuffix: @"%"]) a /= 100.0;
      return [NSColor colorWithCalibratedRed: [parts[0] doubleValue] / 255.0
                                       green: [parts[1] doubleValue] / 255.0
                                        blue: [parts[2] doubleValue] / 255.0 alpha: a];
    }
  if ([c isEqualToString: @"transparent"]) return [NSColor clearColor];
  if ([c isEqualToString: @"black"]) return [NSColor blackColor];
  if ([c isEqualToString: @"white"]) return [NSColor whiteColor];
  if ([c isEqualToString: @"gray"] || [c isEqualToString: @"grey"]) return [NSColor grayColor];
  if ([c isEqualToString: @"red"]) return [NSColor redColor];
  if ([c isEqualToString: @"green"]) return [NSColor colorWithCalibratedRed: 0 green: 0.5 blue: 0 alpha: 1];
  if ([c isEqualToString: @"blue"]) return [NSColor blueColor];
  return nil;
}

/* ------------------------------------------------------------------ */
#pragma mark Text styling of leaf controls

static void TRApplyTextStyle(NSView *view, NSDictionary *decls)
{
  if ([view isKindOfClass: [NSScrollView class]])
    {
      NSString *bg = decls[@"background-color"] ?: decls[@"background"];
      NSColor *c = bg ? TRColorFromCSS(bg) : nil;
      if (c)
        {
          [(NSScrollView *)view setBackgroundColor: c];
          [(NSScrollView *)view setDrawsBackground: YES];
        }
      return;
    }
  if (![view isKindOfClass: [NSControl class]] || [decls count] == 0) return;
  NSControl *ctl = (NSControl *)view;
  NSString *v;
  NSFont *font = [ctl font];
  if (font != nil && ((v = decls[@"font-size"]) != nil || decls[@"font-weight"] != nil))
    {
      CGFloat size = v ? [v doubleValue] : [font pointSize];
      NSString *w = decls[@"font-weight"];
      BOOL bold = w && ([w isEqualToString: @"bold"] || [w integerValue] >= 600);
      NSFont *f = bold ? [NSFont boldSystemFontOfSize: size] : [NSFont systemFontOfSize: size];
      if (f) [ctl setFont: f];
    }
  if ((v = decls[@"color"]) != nil && [ctl respondsToSelector: @selector(setTextColor:)])
    {
      NSColor *col = TRColorFromCSS(v);
      if (col) [(NSTextField *)ctl setTextColor: col];
    }
  if ((v = decls[@"text-align"]) != nil)
    {
      NSTextAlignment a = NSLeftTextAlignment;
      if ([v isEqualToString: @"center"]) a = NSCenterTextAlignment;
      else if ([v isEqualToString: @"right"] || [v isEqualToString: @"end"]) a = NSRightTextAlignment;
      [ctl setAlignment: a];
    }
  if ((v = decls[@"white-space"]) != nil)
    {
      BOOL wrap = ![v isEqualToString: @"nowrap"] && ![v isEqualToString: @"pre"];
      [[ctl cell] setWraps: wrap];
    }
}

/* ------------------------------------------------------------------ */

@implementation TRBoxView
{
  TRNode *_node;
  NSString *_pendingDeclarations;
  NSMapTable *_signatures;        /* view -> content signature */
  NSMapTable *_appliedStyles;     /* view -> style last pushed to the control */
  BOOL _applyingFrames;
  BOOL _layoutScheduled;
}

+ (instancetype)boxWithStyle:(NSString *)declarations
{
  return [[self alloc] initWithStyle: declarations];
}

- (instancetype)initWithStyle:(NSString *)declarations
{
  if ((self = [self initWithFrame: NSMakeRect(0, 0, 100, 100)]) != nil)
    {
      if (declarations) [self setStyleDeclarations: declarations];
    }
  return self;
}

- (instancetype)initWithFrame:(NSRect)frame
{
  if ((self = [super initWithFrame: frame]) != nil)
    {
      _node = [TRNode node];
      _node.context = self;
      _signatures = [NSMapTable weakToStrongObjectsMapTable];
      _appliedStyles = [NSMapTable weakToWeakObjectsMapTable];
      [self setAutoresizesSubviews: NO];
    }
  return self;
}

- (BOOL)isFlipped
{
  return YES;
}

- (TRNode *)node
{
  return _node;
}

- (TRStyle *)style
{
  return _node.style;
}

- (void)setStyle:(TRStyle *)style
{
  _node.style = style;
  [self setNeedsDisplay: YES];
  [self scheduleLayout];
}

- (void)setStyleDeclarations:(NSString *)declarations
{
  NSError *err = nil;
  if (![_node.style applyDeclarations: declarations error: &err])
    [NSException raise: NSInvalidArgumentException
                format: @"Trellis: bad style \"%@\": %@", declarations, [err localizedDescription]];
  [self setNeedsDisplay: YES];
  [self scheduleLayout];
}

/* ---- Children ---- */

- (void)addSubview:(NSView *)view style:(NSString *)declarations
{
  _pendingDeclarations = declarations;
  [self addSubview: view];
  _pendingDeclarations = nil;
}

- (void)didAddSubview:(NSView *)view
{
  [super didAddSubview: view];
  if ([self nodeForSubview: view] == nil)
    [self attachSubview: view declarations: _pendingDeclarations];
}

- (void)willRemoveSubview:(NSView *)view
{
  TRNode *n = [self nodeForSubview: view];
  if (n != nil) [_node removeChild: n];
  [_signatures removeObjectForKey: view];
  [super willRemoveSubview: view];
  [self scheduleLayout];
}

- (void)attachSubview:(NSView *)view declarations:(NSString *)declarations
{
  TRNode *n;
  if ([view isKindOfClass: [TRBoxView class]])
    n = [(TRBoxView *)view node];
  else
    {
      n = [TRNode node];
      n.context = view;
      __weak NSView *wv = view;
      /* Non-wrapping controls measure the same at any width: memoize on
         the content signature, so live resize does no text measuring. */
      __block NSString *memoSig = nil;
      __block TRSize memoSize;
      n.measureBlock = ^TRSize(TRSize avail, TRMeasureMode wm, TRMeasureMode hm) {
        NSView *v = wv;
        BOOL wraps = [v isKindOfClass: [NSControl class]] && [[(NSControl *)v cell] wraps];
        if (!wraps)
          {
            NSString *sig = TRContentSignature(v);
            if (memoSig != nil && [sig isEqualToString: memoSig]) return memoSize;
            memoSize = TRMeasureView(v, avail, wm, hm);
            memoSig = sig;
            return memoSize;
          }
        return TRMeasureView(v, avail, wm, hm);
      };
      n.baselineBlock = ^TRFloat(TRSize size) {
        return TRBaselineOfView(wv, size);
      };
    }
  if ([view respondsToSelector: @selector(identifier)])
    {
      NSString *ident = [(id)view identifier];
      if ([ident length]) n.identifier = ident;
    }
  [_node addChild: n];
  if (declarations) [self setStyleDeclarations: declarations forSubview: view];
  [self scheduleLayout];
}

- (TRNode *)nodeForSubview:(NSView *)view
{
  for (TRNode *c in _node.children)
    if (c.context == view) return c;
  return nil;
}

- (void)setStyleDeclarations:(NSString *)declarations forSubview:(NSView *)view
{
  TRNode *n = [self nodeForSubview: view];
  if (n == nil) return;
  NSError *err = nil;
  if (![n.style applyDeclarations: declarations error: &err])
    [NSException raise: NSInvalidArgumentException
                format: @"Trellis: bad style \"%@\" for %@: %@", declarations, view,
                        [err localizedDescription]];
  TRApplyTextStyle(view, n.style.otherDeclarations);
  if ([view isKindOfClass: [TRBoxView class]]) [view setNeedsDisplay: YES];
  [_signatures removeObjectForKey: view];
  [self scheduleLayout];
}

- (void)addConditionalStyle:(NSString *)declarations when:(NSString *)condition
{
  NSError *err = nil;
  if (![_node addConditionalStyle: declarations when: condition error: &err])
    [NSException raise: NSInvalidArgumentException format: @"Trellis: %@", [err localizedDescription]];
  [self scheduleLayout];
}

- (void)addConditionalStyle:(NSString *)declarations when:(NSString *)condition
                 forSubview:(NSView *)view
{
  TRNode *n = [self nodeForSubview: view];
  NSError *err = nil;
  if (n == nil || ![n addConditionalStyle: declarations when: condition error: &err])
    [NSException raise: NSInvalidArgumentException format: @"Trellis: %@",
                 err ? [err localizedDescription] : @"not a subview of this box"];
  [self scheduleLayout];
}

- (void)invalidateSubview:(NSView *)view
{
  [[self nodeForSubview: view] markDirty];
  [_signatures removeObjectForKey: view];
  [self scheduleLayout];
}

/* ---- Layout ---- */

- (BOOL)isNestedBox
{
  NSView *sv = [self superview];
  return [sv isKindOfClass: [TRBoxView class]] && _node.parent == [(TRBoxView *)sv node];
}

- (TRBoxView *)rootBox
{
  TRBoxView *b = self;
  while ([b isNestedBox]) b = (TRBoxView *)[b superview];
  return b;
}

- (void)scheduleLayout
{
  TRBoxView *root = [self rootBox];
  if (root != self) { [root scheduleLayout]; return; }
  if (_layoutScheduled) return;
  _layoutScheduled = YES;
  [self performSelector: @selector(runScheduledLayout) withObject: nil afterDelay: 0];
}

- (void)runScheduledLayout
{
  if (_layoutScheduled) [self layoutTrellis];
}

/* Remeasure leaves whose content changed since the last layout. */
- (void)refreshSignatures
{
  for (TRNode *c in _node.children)
    {
      NSView *v = c.context;
      if ([v isKindOfClass: [TRBoxView class]])
        {
          [(TRBoxView *)v refreshSignatures];
          continue;
        }
      NSString *sig = TRContentSignature(v);
      NSString *old = [_signatures objectForKey: v];
      if (old == nil || ![old isEqualToString: sig])
        {
          [c markDirty];
          [_signatures setObject: sig forKey: v];
        }
    }
}

- (void)layoutTrellis
{
  TRBoxView *root = [self rootBox];
  if (root != self) { [root layoutTrellis]; return; }
  _layoutScheduled = NO;
  [self refreshSignatures];
  NSSize sz = [self bounds].size;
  [_node layoutWithAvailableSize: TRSizeMake(sz.width, sz.height)];
  [self applyFrames];
}

- (void)applyFrames
{
  _applyingFrames = YES;
  for (TRNode *c in _node.children)
    {
      NSView *v = c.context;
      if (v == nil) continue;
      TRRect f = c.layoutFrame;
      /* Container queries may have swapped the style: push text styling. */
      TRStyle *st = c.style;
      if ([_appliedStyles objectForKey: v] != st)
        {
          TRApplyTextStyle(v, st.otherDeclarations);
          [_appliedStyles setObject: st forKey: v];
          if ([v isKindOfClass: [TRBoxView class]]) [v setNeedsDisplay: YES];
        }
      BOOL hidden = (st.display == TRDisplayNone);
      [v setHidden: hidden];
      if (!hidden) [v setFrame: NSMakeRect(f.x, f.y, f.width, f.height)];
      if ([v isKindOfClass: [TRBoxView class]]) [(TRBoxView *)v applyFrames];
    }
  _applyingFrames = NO;
  [self setNeedsDisplay: YES];
}

- (void)setFrameSize:(NSSize)size
{
  NSSize old = [self frame].size;
  [super setFrameSize: size];
  if (![self isNestedBox] && !NSEqualSizes(old, size))
    [self layoutTrellis];
}

/* GNUstep's -setFrame: does not call -setFrameSize:. */
- (void)setFrame:(NSRect)frame
{
  NSSize old = [self frame].size;
  [super setFrame: frame];
  if (![self isNestedBox] && !NSEqualSizes(old, frame.size))
    [self layoutTrellis];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
  /* Trellis positions the subviews; nothing to do here. */
}

- (NSSize)intrinsicContentSize
{
  [_node layoutWithAvailableSize: TRSizeMake(NAN, NAN)];
  TRRect f = _node.layoutFrame;
  NSSize s = NSMakeSize(f.width, f.height);
  /* Restore the layout for the current size. */
  if (![self isNestedBox]) [self layoutTrellis];
  return s;
}

/* ---- Drawing ---- */

- (void)drawRect:(NSRect)dirty
{
  NSDictionary *d = _node.style.otherDeclarations;
  NSString *bg = d[@"background-color"] ?: d[@"background"];
  NSString *bc = d[@"border-color"];
  CGFloat radius = [d[@"border-radius"] doubleValue];
  CGFloat bw = [_node layoutBorderForEdge: TREdgeTop];
  NSRect r = [self bounds];
  if (bg)
    {
      NSColor *c = TRColorFromCSS(bg);
      if (c)
        {
          [c set];
          [[NSBezierPath bezierPathWithRoundedRect: r xRadius: radius yRadius: radius] fill];
        }
    }
  if (bw > 0)
    {
      NSColor *c = bc ? TRColorFromCSS(bc) : [NSColor grayColor];
      if (c)
        {
          [c set];
          NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(r, bw / 2, bw / 2)
                                                            xRadius: radius yRadius: radius];
          [p setLineWidth: bw];
          [p stroke];
        }
    }
}

@end
