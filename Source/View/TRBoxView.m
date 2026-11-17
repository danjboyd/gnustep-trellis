/* TRBoxView.m - an NSView container laid out by Trellis.

   Only public AppKit API is used, so this builds unchanged on GNUstep and
   on macOS.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRBoxView.h"
#import "TRViewMeasure.h"
#import <objc/runtime.h>
#import <objc/message.h>

static char kTRTabIndexKey, kTRA11yLabelKey, kTRA11yTitleKey, kTRA11yRoleKey, kTRA11yCollectionKey, kTRA11yPositionKey;

/* Cocoa's NSAccessibility setters, called only where they exist. */
static void TRSendObject(NSView *v, NSString *selName, id value)
{
  SEL sel = NSSelectorFromString(selName);
  if ([v respondsToSelector: sel]) ((void (*)(id, SEL, id))objc_msgSend)(v, sel, value);
}

static void TRSendBool(NSView *v, NSString *selName, BOOL value)
{
  SEL sel = NSSelectorFromString(selName);
  if ([v respondsToSelector: sel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(v, sel, value);
}

static void TRSendInteger(NSView *v, NSString *selName, NSInteger value)
{
  SEL sel = NSSelectorFromString(selName);
  if ([v respondsToSelector: sel]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(v, sel, value);
}

void TRSetAccessibilityLabel(NSView *view, NSString *label)
{
  objc_setAssociatedObject(view, &kTRA11yLabelKey, [label copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  TRSendObject(view, @"setAccessibilityLabel:", label);
}

NSString *TRAccessibilityLabel(NSView *view)
{
  NSString *l = objc_getAssociatedObject(view, &kTRA11yLabelKey);
  if ([l length]) return l;
  NSView *t = TRAccessibilityTitleView(view);
  if ([t isKindOfClass: [NSTextField class]]) return [(NSTextField *)t stringValue];
  return nil;
}

void TRSetAccessibilityTitleView(NSView *view, NSView *titleView)
{
  objc_setAssociatedObject(view, &kTRA11yTitleKey, titleView, OBJC_ASSOCIATION_ASSIGN);
  TRSendObject(view, @"setAccessibilityTitleUIElement:", titleView);
  if (titleView) TRSendObject(titleView, @"setAccessibilityServesAsTitleForUIElements:", @[view]);
}

NSView *TRAccessibilityTitleView(NSView *view)
{
  return objc_getAssociatedObject(view, &kTRA11yTitleKey);
}

void TRSetAccessibilityRole(NSView *view, NSString *role)
{
  objc_setAssociatedObject(view, &kTRA11yRoleKey, [role copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  if ([role isEqualToString: @"none"])
    TRSendBool(view, @"setAccessibilityElement:", NO);
  else if ([role isEqualToString: @"group"])
    {
      TRSendBool(view, @"setAccessibilityElement:", YES);
      TRSendObject(view, @"setAccessibilityRole:", @"AXGroup");   /* NSAccessibilityGroupRole */
    }
}

NSString *TRAccessibilityRole(NSView *view)
{
  return objc_getAssociatedObject(view, &kTRA11yRoleKey);
}

void TRSetAccessibilityCollection(NSView *view, NSString *role, NSInteger count, NSInteger columns)
{
  objc_setAssociatedObject(view, &kTRA11yRoleKey, [role copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(view, &kTRA11yCollectionKey, @[@(count), @(columns)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  TRSendBool(view, @"setAccessibilityElement:", YES);
  TRSendObject(view, @"setAccessibilityRole:", [role isEqualToString: @"grid"] ? @"AXGrid" : @"AXList");
  TRSendInteger(view, @"setAccessibilityRowCount:", columns > 0 ? (count + columns - 1) / columns : count);
  if (columns > 0) TRSendInteger(view, @"setAccessibilityColumnCount:", columns);
}

BOOL TRAccessibilityCollection(NSView *view, NSInteger *count, NSInteger *columns)
{
  NSArray *a = objc_getAssociatedObject(view, &kTRA11yCollectionKey);
  if (a == nil) return NO;
  if (count) *count = [a[0] integerValue];
  if (columns) *columns = [a[1] integerValue];
  return YES;
}

void TRSetAccessibilityPosition(NSView *view, NSInteger index, NSInteger row, NSInteger column)
{
  objc_setAssociatedObject(view, &kTRA11yPositionKey, @[@(index), @(row), @(column)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  TRSendInteger(view, @"setAccessibilityIndex:", index);
}

BOOL TRAccessibilityPosition(NSView *view, NSInteger *index, NSInteger *row, NSInteger *column)
{
  NSArray *a = objc_getAssociatedObject(view, &kTRA11yPositionKey);
  if (a == nil) return NO;
  if (index) *index = [a[0] integerValue];
  if (row) *row = [a[1] integerValue];
  if (column) *column = [a[2] integerValue];
  return YES;
}

void TRSetTabIndex(NSView *view, NSInteger index)
{
  objc_setAssociatedObject(view, &kTRTabIndexKey, index ? @(index) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

NSInteger TRTabIndex(NSView *view)
{
  return [objc_getAssociatedObject(view, &kTRTabIndexKey) integerValue];
}

/* ------------------------------------------------------------------ */
#pragma mark Colours

static CGFloat TRHex(NSString *s, NSUInteger i, NSUInteger len)
{
  unsigned v = 0;
  [[NSScanner scannerWithString: [s substringWithRange: NSMakeRange(i, len)]] scanHexInt: &v];
  return len == 1 ? (v * 17) / 255.0 : v / 255.0;
}

/* A fixed CSS colour. CSS hex and rgb() are sRGB: on Cocoa make them in
   sRGB (calibrated would be generic RGB, and shift on screen); GNUstep
   treats calibrated RGB as sRGB. */
static NSColor *TRSRGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a)
{
#ifdef GNUSTEP
  return [NSColor colorWithCalibratedRed: r green: g blue: b alpha: a];
#else
  return [NSColor colorWithSRGBRed: r green: g blue: b alpha: a];
#endif
}

NSColor *TRColorFromCSS(NSString *css)
{
  NSString *c = [[css stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]] lowercaseString];
  if ([c hasPrefix: @"#"])
    {
      NSString *h = [c substringFromIndex: 1];
      NSUInteger n = [h length];
      if (n == 3 || n == 4)
        return TRSRGB(TRHex(h, 0, 1), TRHex(h, 1, 1), TRHex(h, 2, 1), n == 4 ? TRHex(h, 3, 1) : 1);
      if (n == 6 || n == 8)
        return TRSRGB(TRHex(h, 0, 2), TRHex(h, 2, 2), TRHex(h, 4, 2), n == 8 ? TRHex(h, 6, 2) : 1);
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
      return TRSRGB([parts[0] doubleValue] / 255.0, [parts[1] doubleValue] / 255.0,
                    [parts[2] doubleValue] / 255.0, a);
    }
  /* CSS system colours (CSS Color 4) map to AppKit's dynamic colours, so
     they follow the appearance (Light/Dark on macOS, the theme on
     GNUstep). Use them instead of fixed colours for backgrounds and text. */
  {
    static NSDictionary *sys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      sys = @{ @"canvas": @"textBackgroundColor", @"canvastext": @"textColor",
               @"field": @"controlBackgroundColor", @"fieldtext": @"controlTextColor",
               @"buttonface": @"controlColor", @"buttontext": @"controlTextColor",
               @"buttonborder": @"gridColor",
               @"graytext": @"secondaryLabelColor|disabledControlTextColor",
               @"highlight": @"selectedTextBackgroundColor", @"highlighttext": @"selectedTextColor",
               @"selecteditem": @"selectedContentBackgroundColor|selectedControlColor",
               @"selecteditemtext": @"alternateSelectedControlTextColor",
               @"accentcolor": @"controlAccentColor|selectedControlColor",
               @"accentcolortext": @"alternateSelectedControlTextColor",
               @"linktext": @"linkColor|selectedControlColor|blueColor",
               @"mark": @"findHighlightColor|yellowColor", @"marktext": @"blackColor",   /* Mark is a light highlight in both appearances */
               /* Trellis extensions */
               @"-tr-window-background": @"windowBackgroundColor",
               @"-tr-separator": @"separatorColor|gridColor",
               @"-tr-secondary-text": @"secondaryLabelColor|disabledControlTextColor",
               @"-tr-error": @"systemRedColor|redColor" };
    });
    /* Soft warning tint: like Mark, a light pair that reads the same in
       both appearances (fixed, so it never flips to a dark brown). */
    if ([c isEqualToString: @"-tr-warning-background"])
      return TRSRGB(0xFC/255.0, 0xEE/255.0, 0xDD/255.0, 1);
    if ([c isEqualToString: @"-tr-warning-text"])
      return TRSRGB(0x8A/255.0, 0x3B/255.0, 0x06/255.0, 1);
    NSString *names = sys[c];
    if (names != nil)
      for (NSString *name in [names componentsSeparatedByString: @"|"])
        {
          SEL sel = NSSelectorFromString(name);
          if ([NSColor respondsToSelector: sel])
            return ((NSColor *(*)(id, SEL))[NSColor methodForSelector: sel])([NSColor class], sel);
        }
  }
  if ([c isEqualToString: @"transparent"]) return [NSColor clearColor];
  if ([c isEqualToString: @"black"]) return [NSColor blackColor];
  if ([c isEqualToString: @"white"]) return [NSColor whiteColor];
  if ([c isEqualToString: @"gray"] || [c isEqualToString: @"grey"]) return [NSColor grayColor];
  if ([c isEqualToString: @"red"]) return [NSColor redColor];
  if ([c isEqualToString: @"green"]) return TRSRGB(0, 0.5, 0, 1);
  if ([c isEqualToString: @"blue"]) return [NSColor blueColor];
  return nil;
}

/* ------------------------------------------------------------------ */
#pragma mark Text styling of leaf controls

static void TRApplyTextStyle(NSView *view, NSDictionary *decls);

void TRApplyLeafStyle(NSView *view, NSString *declarations)
{
  TRStyle *st = [TRStyle new];
  if ([declarations length]) [st applyDeclarations: declarations error: NULL];
  TRApplyTextStyle(view, st.otherDeclarations);
}

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
  else if (v != nil && [ctl isKindOfClass: [NSButton class]])
    {
      /* Buttons have no text colour; colour the title instead (for flat,
         bordered="no" buttons on a coloured bar). A later -setTitle:
         drops it; set -attributedTitle, or call -invalidateSubview:. */
      NSColor *col = TRColorFromCSS(v);
      NSButton *b = (NSButton *)ctl;
      if (col)
        {
          NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
          [ps setAlignment: NSCenterTextAlignment];
          NSDictionary *attrs = @{ NSForegroundColorAttributeName: col,
                                   NSFontAttributeName: [b font] ?: [NSFont systemFontOfSize: 0],
                                   NSParagraphStyleAttributeName: ps };
          [b setAttributedTitle: [[NSAttributedString alloc] initWithString: [b title] attributes: attrs]];
        }
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
  /* Rich labels rebuild their runs over the new font and colour. */
  if ([ctl respondsToSelector: @selector(trellisRebuildRichText)])
    [ctl performSelector: @selector(trellisRebuildRichText)];
}

/* ------------------------------------------------------------------ */

/* The target of a box's deferred layout. It holds the box weakly, so a
   box freed with a layout pending is never messaged: GNUstep's delayed
   performer doesn't keep a deallocating target alive. */
@interface TRLayoutTrigger : NSObject
{
@public
  __weak TRBoxView *box;
}
- (void)fire;
@end

@interface TRBoxView ()
- (void)runScheduledLayout;
@end

/* An ARC weak reference. GNUstep's weak NSHashTable can hand back an
   object that is being deallocated; an ARC __weak load returns nil. */
@interface TRWeakView : NSObject
{
@public
  __weak NSView *view;
}
@end
@implementation TRWeakView
@end

#ifdef GNUSTEP
/* The wrap point of a managed key-view chain on GNUstep: last -> sentinel
   -> first. GNUstep's -nextValidKeyView walks nextKeyView until it finds
   a view that can become key, nil or its start, so a closed ring whose
   members are all hidden or disabled made it spin. The sentinel leads
   back in only while a member can take focus, and is nil otherwise.
   Its getters never return NSView's raw link, only the box's __weak
   first/last (nil for a view being freed): GNUstep's -dealloc calls
   -nextKeyView on neighbours, and ARC would retain and autorelease a
   dying view on the way out. It is never added to a window. */
@interface TRKeyLoopSentinel : NSView
{
@public
  NSArray *members;              /* TRWeakView, shared with the box */
  __weak NSView *first, *last;
  BOOL tearingDown;
}
@end

@implementation TRKeyLoopSentinel
- (void)dealloc { tearingDown = YES; }
- (BOOL)acceptsFirstResponder { return NO; }
- (BOOL)hasValidMember
{
  for (TRWeakView *w in members)
    {
      NSView *v = w->view;
      if (v != nil && [v canBecomeKeyView]) return YES;
    }
  return NO;
}
- (NSView *)nextKeyView
{
  if (tearingDown) return nil;
  NSView *f = first;
  return (f != nil && [self hasValidMember]) ? f : nil;
}
- (NSView *)previousKeyView
{
  if (tearingDown) return nil;
  NSView *l = last;
  return (l != nil && [self hasValidMember]) ? l : nil;
}
@end
#endif

@implementation TRLayoutTrigger
- (void)fire
{
  TRBoxView *b = box;
  [b runScheduledLayout];
}
@end

/* The target of a box's animation timer, holding the box weakly (an
   NSTimer retains its target). */
@interface TRAnimationTicker : NSObject
{
@public
  __weak TRBoxView *box;
}
- (void)tick:(NSTimer *)timer;
@end

@interface TRBoxView ()
- (void)animationTick;
@end

@implementation TRAnimationTicker
- (void)tick:(NSTimer *)timer
{
  TRBoxView *b = box;
  if (b == nil) { [timer invalidate]; return; }
  [b animationTick];
}
@end

/* One view moving from one frame to another. */
@interface TRFrameAnimation : NSObject
{
@public
  __weak NSView *view;
  NSRect from, to;
}
@end
@implementation TRFrameAnimation
@end

/* Set by the root while it applies frames for an animated layout. */
static NSMutableArray<TRFrameAnimation *> *gTRCollecting;

static NSNumber *gTRReduceMotionOverride;
static NSNumber *gTRAnimationTimeOverride;

/* The animation clock: real time, or the test's (setAnimationTimeOverride:). */
static NSTimeInterval TRAnimationNow(void)
{
  return gTRAnimationTimeOverride ? [gTRAnimationTimeOverride doubleValue]
                                  : [NSDate timeIntervalSinceReferenceDate];
}

/* -tr-layout-transition: <time> [easing] | none. Returns the duration in
   seconds (0 = none), or -1 when the style doesn't say. */
static double TRTransitionOf(TRStyle *st, int *easing)
{
  NSString *v = st.otherDeclarations[@"-tr-layout-transition"];
  if (v == nil) return -1;
  double d = 0;
  int e = 0;   /* 0 ease-out, 1 linear, 2 ease-in-out */
  for (NSString *tok in [v componentsSeparatedByCharactersInSet: [NSCharacterSet whitespaceCharacterSet]])
    {
      if ([tok hasSuffix: @"ms"]) d = [tok doubleValue] / 1000.0;
      else if ([tok hasSuffix: @"s"]) d = [tok doubleValue];
      else if ([tok isEqualToString: @"linear"]) e = 1;
      else if ([tok isEqualToString: @"ease-in-out"] || [tok isEqualToString: @"ease"]) e = 2;
    }
  if (easing) *easing = e;
  return MAX(d, 0);
}

static double TREase(double t, int easing)
{
  t = MAX(0, MIN(1, t));
  if (easing == 1) return t;
  if (easing == 2) return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2;
  return 1 - pow(1 - t, 3);
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
  BOOL _tearingDown;
  TRLayoutTrigger *_trigger;
  BOOL _managesKeyViewLoop;
  __weak NSView *_firstKeyView;
  __weak NSView *_lastKeyView;
  NSMutableArray *_keyLoopViews;  /* TRWeakView: the views linked last time */
#ifdef GNUSTEP
  TRKeyLoopSentinel *_keyLoopSentinel;
#endif
  /* Layout transitions (on the root). */
  BOOL _animateNextLayout;
  NSMutableArray<TRFrameAnimation *> *_animations;
  NSTimer *_animationTimer;
  NSTimeInterval _animationStart, _animationDuration;
  int _animationEasing;
  double _collectedDuration;
  int _collectedEasing;
  NSHashTable *_placed;           /* subviews laid out at least once */
}

+ (BOOL)reducesMotion
{
  if (gTRReduceMotionOverride) return [gTRReduceMotionOverride boolValue];
  const char *env = getenv("TRELLIS_REDUCE_MOTION");
  if (env && *env && strcmp(env, "0") != 0) return YES;
  if ([[NSUserDefaults standardUserDefaults] boolForKey: @"TRReduceMotion"]) return YES;
#ifndef GNUSTEP
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  if ([ws respondsToSelector: @selector(accessibilityDisplayShouldReduceMotion)])
    return [ws accessibilityDisplayShouldReduceMotion];
#endif
  return NO;
}

+ (void)setReducesMotionOverride:(NSNumber *)reduce
{
  gTRReduceMotionOverride = reduce;
}

+ (void)setAnimationTimeOverride:(NSNumber *)seconds
{
  gTRAnimationTimeOverride = seconds;
}

- (void)stepLayoutAnimation
{
  TRBoxView *root = [self rootBox];
  if (root->_animationTimer != nil) [root animationTick];
}

- (BOOL)isAnimatingLayout
{
  return _animationTimer != nil;
}

- (void)layoutTrellisAnimated
{
  TRBoxView *root = [self rootBox];
  root->_animateNextLayout = YES;
  [root layoutTrellis];
}

- (void)finishLayoutAnimation
{
  [_animationTimer invalidate];
  _animationTimer = nil;
  for (TRFrameAnimation *a in _animations)
    {
      NSView *v = a->view;
      if (v) [v setFrame: a->to];
    }
  _animations = nil;
}

- (void)animationTick
{
  NSTimeInterval t = _animationDuration > 0
    ? (TRAnimationNow() - _animationStart) / _animationDuration : 1;
  if (t >= 1) { [self finishLayoutAnimation]; return; }
  double k = TREase(t, _animationEasing);
  for (TRFrameAnimation *a in _animations)
    {
      NSView *v = a->view;
      if (v == nil) continue;
      NSRect f = NSMakeRect(a->from.origin.x + (a->to.origin.x - a->from.origin.x) * k,
                            a->from.origin.y + (a->to.origin.y - a->from.origin.y) * k,
                            a->from.size.width + (a->to.size.width - a->from.size.width) * k,
                            a->from.size.height + (a->to.size.height - a->from.size.height) * k);
      [v setFrame: f];
    }
  [self setNeedsDisplay: YES];
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
      _placed = [NSHashTable weakObjectsHashTable];
      _appliedStyles = [NSMapTable weakToWeakObjectsMapTable];
      _managesKeyViewLoop = YES;
      [self setAutoresizesSubviews: NO];
    }
  return self;
}

- (void)dealloc
{
  /* NSView's teardown removes the subviews, which would schedule a layout
     on this (deallocating) box. */
  _tearingDown = YES;
  if (_trigger != nil)
    {
      [NSObject cancelPreviousPerformRequestsWithTarget: _trigger];
      _trigger->box = nil;
    }
  [_animationTimer invalidate];
  _animationTimer = nil;
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
  else if ([view isKindOfClass: [NSScrollView class]])
    {
      /* A scroll view has no intrinsic size, so it gets no measure block:
         it lays out as an empty box, sized by its style. (A measured node
         is rounded to the pixel grid as text is, floor/ceil, which can
         overlap a neighbour by a pixel.) */
      n = [TRNode node];
      n.context = view;
    }
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
        /* Width-dependent views (TRSizeForWidth) are never memoized. */
        if ([v respondsToSelector: @selector(trellisSizeForWidth:)])
          return TRMeasureView(v, avail, wm, hm);
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
  if (_tearingDown) return;
  TRBoxView *root = [self rootBox];
  if (root != self) { [root scheduleLayout]; return; }
  if (_layoutScheduled) return;
  _layoutScheduled = YES;
  if (_trigger == nil)
    {
      _trigger = [TRLayoutTrigger new];
      _trigger->box = self;
    }
  [_trigger performSelector: @selector(fire) withObject: nil afterDelay: 0];
}

- (void)runScheduledLayout
{
  /* Content and style changes animate (if the style asks); resizes don't. */
  if (_layoutScheduled) { _animateNextLayout = YES; [self layoutTrellis]; }
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

- (CGFloat)heightForWidth:(CGFloat)width
{
  [self refreshSignatures];
  [_node layoutWithAvailableSize: TRSizeMake(width, NAN)];
  CGFloat h = _node.layoutFrame.height;
  NSSize sz = [self bounds].size;
  [_node layoutWithAvailableSize: TRSizeMake(sz.width, sz.height)];
  return h;
}

- (void)layoutTrellis
{
  TRBoxView *root = [self rootBox];
  if (root != self) { [root layoutTrellis]; return; }
  _layoutScheduled = NO;
  BOOL animate = _animateNextLayout && ![[self class] reducesMotion] && [self window] != nil
                 && ![self inLiveResize];
  _animateNextLayout = NO;
  [self refreshSignatures];
  NSSize sz = [self bounds].size;
  [_node layoutWithAvailableSize: TRSizeMake(sz.width, sz.height)];
  /* A running animation ends where it was heading before the new frames
     go in; an animated layout then starts from the views' current frames. */
  NSMutableDictionary *current = nil;
  if (_animationTimer != nil)
    {
      if (animate)
        {
          current = [NSMutableDictionary dictionary];
          for (TRFrameAnimation *a in _animations)
            {
              NSView *v = a->view;
              if (v) current[[NSValue valueWithNonretainedObject: v]] = [NSValue valueWithRect: [v frame]];
            }
        }
      [self finishLayoutAnimation];
    }
  NSMutableArray *collected = nil;
  _collectedDuration = 0;
  _collectedEasing = 0;
  if (animate)
    {
      collected = [NSMutableArray array];
      gTRCollecting = collected;
    }
  [self applyFramesInheriting: -1 easing: 0];
  gTRCollecting = nil;
  if ([collected count])
    {
      double duration;
      int easing;
      for (TRFrameAnimation *a in collected)
        {
          NSValue *cur = current[[NSValue valueWithNonretainedObject: a->view]];
          if (cur) a->from = [cur rectValue];
        }
      /* The longest duration among the moving views' boxes. */
      duration = _collectedDuration;
      easing = _collectedEasing;
      _animations = collected;
      _animationDuration = duration;
      _animationEasing = easing;
      _animationStart = TRAnimationNow();
      for (TRFrameAnimation *a in collected)
        {
          NSView *v = a->view;
          if (v) [v setFrame: a->from];
        }
      TRAnimationTicker *tk = [TRAnimationTicker new];
      tk->box = self;
      _animationTimer = [NSTimer timerWithTimeInterval: 1.0 / 60 target: tk selector: @selector(tick:)
                                              userInfo: nil repeats: YES];
      [[NSRunLoop currentRunLoop] addTimer: _animationTimer forMode: NSDefaultRunLoopMode];
      [[NSRunLoop currentRunLoop] addTimer: _animationTimer forMode: NSModalPanelRunLoopMode];
    }
  [self recalculateTrellisKeyViewLoop];
}

/* ---- Keyboard focus order ---- */

- (BOOL)managesKeyViewLoop { return _managesKeyViewLoop; }
- (void)setManagesKeyViewLoop:(BOOL)yn
{
  _managesKeyViewLoop = yn;
  if (!yn)
    {
      /* Hand the chain back: unlink what Trellis linked; the app links
         its own views now. */
      for (TRWeakView *w in _keyLoopViews)
        {
          NSView *v = w->view;
          if (v != nil) [v setNextKeyView: nil];
        }
      _keyLoopViews = nil;
      _firstKeyView = nil;
      _lastKeyView = nil;
#ifdef GNUSTEP
      [_keyLoopSentinel setNextKeyView: nil];
      _keyLoopSentinel = nil;
#endif
    }
}
- (NSView *)firstKeyView { return _firstKeyView; }

/* Focusable views under v in document order (a TRBoxView's subviews in
   node order, a scroller's document view, other containers' subviews). */
static void TRCollectKeyViews(NSView *v, NSMutableArray *out)
{
  if ([v isHidden]) return;
  if ([v isKindOfClass: [TRBoxView class]])
    {
      for (TRNode *c in ((TRBoxView *)v).node.children)
        if ([c.context isKindOfClass: [NSView class]]) TRCollectKeyViews(c.context, out);
      return;
    }
  if ([v conformsToProtocol: @protocol(TRKeyViewProvider)])
    {
      for (NSView *sub in [(id<TRKeyViewProvider>)v trellisKeyViewSubtrees]) TRCollectKeyViews(sub, out);
      return;
    }
  if ([v isKindOfClass: [NSScrollView class]])
    {
      NSView *doc = [(NSScrollView *)v documentView];
      if (doc) TRCollectKeyViews(doc, out);
      return;
    }
  if ([v acceptsFirstResponder] || [v canBecomeKeyView])
    {
      if (TRTabIndex(v) >= 0) [out addObject: v];
      return;
    }
  for (NSView *sub in [v subviews]) TRCollectKeyViews(sub, out);
}

- (void)recalculateTrellisKeyViewLoop
{
  if (!_managesKeyViewLoop) return;
  /* Only the outermost Trellis box (scrolled content joins its loop). */
  for (NSView *p = [self superview]; p != nil; p = [p superview])
    if ([p isKindOfClass: [TRBoxView class]]) return;
  NSMutableArray *views = [NSMutableArray array];
  TRCollectKeyViews(self, views);
  /* Positive tab indexes first (ascending, stable), then document order. */
  NSMutableArray *ordered = [NSMutableArray array], *rest = [NSMutableArray array];
  for (NSView *v in views) [(TRTabIndex(v) > 0 ? ordered : rest) addObject: v];
  /* Stable insertion sort by tab index (lists are short). */
  for (NSUInteger i = 1; i < [ordered count]; i++)
    {
      NSView *v = ordered[i];
      NSInteger k = TRTabIndex(v);
      NSUInteger j = i;
      while (j > 0 && TRTabIndex(ordered[j - 1]) > k) { ordered[j] = ordered[j - 1]; j--; }
      ordered[j] = v;
    }
  [ordered addObjectsFromArray: rest];
  /* Unlink views that left the loop, so no stale chain points into it. */
  for (TRWeakView *w in _keyLoopViews)
    {
      NSView *v = w->view;
      if (v != nil && [v nextKeyView] != nil) [v setNextKeyView: nil];
    }
  if (_keyLoopViews == nil) _keyLoopViews = [NSMutableArray array];
  [_keyLoopViews removeAllObjects];
  /* GNUstep: an open chain that wraps through a sentinel (see
     TRKeyLoopSentinel). Cocoa: a closed ring; AppKit's search stops by
     itself, and its bookkeeping relies on the plain getters. */
  NSUInteger n = [ordered count];
#ifdef GNUSTEP
  if (_keyLoopSentinel == nil && n > 0)
    _keyLoopSentinel = [[TRKeyLoopSentinel alloc] initWithFrame: NSZeroRect];
  if (_keyLoopSentinel != nil) _keyLoopSentinel->members = _keyLoopViews;
#endif
  for (NSUInteger i = 0; i < n; i++)
    {
      TRWeakView *w = [TRWeakView new];
      w->view = ordered[i];
      [_keyLoopViews addObject: w];
#ifdef GNUSTEP
      [ordered[i] setNextKeyView: (i + 1 < n) ? ordered[i + 1] : (NSView *)_keyLoopSentinel];
#else
      [ordered[i] setNextKeyView: ordered[(i + 1) % n]];
#endif
    }
  _firstKeyView = n ? ordered[0] : nil;
  _lastKeyView = n ? ordered[n - 1] : nil;
#ifdef GNUSTEP
  if (_keyLoopSentinel != nil)
    {
      _keyLoopSentinel->first = _firstKeyView;
      _keyLoopSentinel->last = _lastKeyView;
      /* The raw link too, so GNUstep's back-pointer bookkeeping matches. */
      [_keyLoopSentinel setNextKeyView: _firstKeyView];
    }
#endif
}

- (void)applyFrames
{
  [self applyFramesInheriting: -1 easing: 0];
}

/* `inherited` is the layout transition in effect from the boxes above
   (-1: none said). While the root collects an animated layout, views
   that move under a transition are recorded instead of jumping. */
- (void)applyFramesInheriting:(double)inherited easing:(int)inheritedEasing
{
  int easing = inheritedEasing;
  double own = TRTransitionOf(_node.style, &easing);
  double transition = own >= 0 ? own : inherited;
  if (own < 0) easing = inheritedEasing;
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
      BOOL wasShown = ![v isHidden] && [_placed containsObject: v];
      [v setHidden: hidden];
      NSRect nf = NSMakeRect(f.x, f.y, f.width, f.height);
      if (!hidden)
        {
          NSRect old = [v frame];
          if (gTRCollecting && transition > 0 && wasShown && !NSEqualRects(old, nf))
            {
              TRFrameAnimation *a = [TRFrameAnimation new];
              a->view = v;
              a->from = old;
              a->to = nf;
              [gTRCollecting addObject: a];
              TRBoxView *root = [self rootBox];
              if (transition > root->_collectedDuration)
                {
                  root->_collectedDuration = transition;
                  root->_collectedEasing = easing;
                }
            }
          [v setFrame: nf];
          [_placed addObject: v];
        }
      if ([v isKindOfClass: [TRBoxView class]])
        [(TRBoxView *)v applyFramesInheriting: transition easing: easing];
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

/* Strokes a uniform border of width bw inside r. dashed: dashes of 3bw
   with gaps of 2bw (roughly what browsers draw); dotted: round dots one
   bw across, a dot's width apart; double: two lines of bw/3 with a bw/3
   gap. Other styles (groove, ridge, inset, outset) draw solid. */
static void TRStrokeBorder(NSRect r, CGFloat bw, CGFloat radius, NSString *style)
{
  if ([style isEqualToString: @"double"] && bw >= 3)
    {
      CGFloat t = bw / 3;
      for (int i = 0; i < 2; i++)
        {
          CGFloat inset = (i == 0) ? t / 2 : bw - t / 2;
          CGFloat rr = MAX(0, radius - (inset - bw / 2));
          NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(r, inset, inset)
                                                            xRadius: rr yRadius: rr];
          [p setLineWidth: t];
          [p stroke];
        }
      return;
    }
  NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(r, bw / 2, bw / 2)
                                                    xRadius: radius yRadius: radius];
  [p setLineWidth: bw];
  if ([style isEqualToString: @"dashed"])
    {
      CGFloat dash[2] = { 3 * bw, 2 * bw };
      [p setLineDash: dash count: 2 phase: 0];
      [p setLineCapStyle: NSButtLineCapStyle];
    }
  else if ([style isEqualToString: @"dotted"])
    {
      /* Zero-length dashes with round caps draw as dots of diameter bw. */
      CGFloat dash[2] = { 0, 2 * bw };
      [p setLineDash: dash count: 2 phase: 0];
      [p setLineCapStyle: NSRoundLineCapStyle];
    }
  [p stroke];
}

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
          TRStrokeBorder(r, bw, radius, [d[@"border-style"] lowercaseString]);
        }
    }
}

@end
