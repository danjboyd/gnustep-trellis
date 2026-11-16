/* TRStyle.m - CSS layout properties and the declaration parser.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRStyle.h"
#import "TRNode.h"
#import "TRGrid.h"

NSString *const TRStyleErrorDomain = @"TRStyleErrorDomain";

TRStyleStorage TRStyleStorageInitial(void)
{
  TRStyleStorage s;
  memset(&s, 0, sizeof s);
  s.display = TRDisplayFlex;
  s.position = TRPositionRelative;
  s.direction = TRDirectionInherit;
  s.flexDirection = TRFlexDirectionRow;
  s.flexWrap = TRFlexWrapNoWrap;
  s.justifyContent = TRAlignNormal;
  s.alignItems = TRAlignNormal;
  s.alignSelf = TRAlignAuto;
  s.alignContent = TRAlignNormal;
  s.overflow = TROverflowVisible;
  s.boxSizing = TRBoxSizingBorderBox;   /* deliberate departure from CSS */
  s.flexGrow = 0;
  s.flexShrink = 1;
  s.flexBasis = TRAuto;
  s.width = s.height = TRAuto;
  s.minWidth = s.minHeight = TRAuto;
  s.maxWidth = s.maxHeight = TRNone;
  s.aspectRatio = TRUndefined;
  for (int i = 0; i < 4; i++)
    {
      s.margin[i] = TRPx(0);
      s.padding[i] = TRPx(0);
      s.border[i] = TRPx(0);
      s.inset[i] = TRAuto;
    }
  s.rowGap = s.columnGap = TRPx(0);
  s.order = 0;
  s.justifyItems = TRAlignNormal;
  s.justifySelf = TRAlignAuto;
  s.gridAutoFlowColumn = NO;
  return s;
}

/* ------------------------------------------------------------------ */
#pragma mark Parsing helpers

static NSError *TRError(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);
static NSError *TRError(NSString *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  NSString *msg = [[NSString alloc] initWithFormat: fmt arguments: ap];
  va_end(ap);
  return [NSError errorWithDomain: TRStyleErrorDomain code: 1
                         userInfo: @{NSLocalizedDescriptionKey: msg}];
}

/* "flexDirection" -> "flex-direction"; "flex-direction" unchanged. */
static NSString *TRKebab(NSString *name)
{
  NSMutableString *out = [NSMutableString stringWithCapacity: [name length] + 4];
  NSUInteger n = [name length];
  for (NSUInteger i = 0; i < n; i++)
    {
      unichar c = [name characterAtIndex: i];
      if (c >= 'A' && c <= 'Z')
        {
          if (i > 0) [out appendString: @"-"];
          [out appendFormat: @"%C", (unichar)(c - 'A' + 'a')];
        }
      else
        [out appendFormat: @"%C", c];
    }
  return out;
}

static NSArray<NSString *> *TRTokens(NSString *value)
{
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *t in [value componentsSeparatedByCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]])
    if ([t length]) [out addObject: t];
  return out;
}

static BOOL TRParseNumber(NSString *s, TRFloat *out)
{
  NSScanner *sc = [NSScanner scannerWithString: s];
  double d;
  if (![sc scanDouble: &d] || ![sc isAtEnd]) return NO;
  *out = d;
  return YES;
}

/* Parses a length-percentage, plus auto/none when allowed. */
static BOOL TRParseLength(NSString *tok, TRValue *out, BOOL allowAuto, BOOL allowNone)
{
  NSString *t = [tok lowercaseString];
  if ([t isEqualToString: @"auto"])
    {
      if (!allowAuto) return NO;
      *out = TRAuto;
      return YES;
    }
  if ([t isEqualToString: @"none"])
    {
      if (!allowNone) return NO;
      *out = TRNone;
      return YES;
    }
  TRFloat v;
  if ([t hasSuffix: @"%"])
    {
      if (!TRParseNumber([t substringToIndex: [t length] - 1], &v)) return NO;
      *out = TRPercent(v);
      return YES;
    }
  if ([t hasSuffix: @"px"])
    t = [t substringToIndex: [t length] - 2];
  else if ([t hasSuffix: @"pt"])
    t = [t substringToIndex: [t length] - 2];
  /* Unitless numbers are accepted as px (CSS only allows 0); trellis-lint
     warns about them. */
  if (!TRParseNumber(t, &v)) return NO;
  *out = TRPx(v);
  return YES;
}

static BOOL TRValueFromObject(id obj, TRValue *out, BOOL allowAuto, BOOL allowNone)
{
  if ([obj isKindOfClass: [NSNumber class]])
    {
      *out = TRPx([obj doubleValue]);
      return YES;
    }
  if ([obj isKindOfClass: [NSString class]])
    return TRParseLength([obj stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceCharacterSet]],
                         out, allowAuto, allowNone);
  return NO;
}

typedef struct { const char *name; int value; } TRKeyword;

static BOOL TRLookup(NSString *tok, const TRKeyword *table, int *out)
{
  const char *s = [[tok lowercaseString] UTF8String];
  for (const TRKeyword *k = table; k->name; k++)
    if (strcmp(k->name, s) == 0) { *out = k->value; return YES; }
  return NO;
}

static const TRKeyword kDisplay[] = {
  {"flex", TRDisplayFlex}, {"none", TRDisplayNone},
  /* No CSS block/inline flow: block is a column flex container. */
  {"block", TRDisplayBlock}, {"inline-flex", TRDisplayFlex},
  {"grid", TRDisplayGrid}, {"inline-grid", TRDisplayGrid}, {NULL, 0}};
static const TRKeyword kPosition[] = {
  {"relative", TRPositionRelative}, {"static", TRPositionStatic},
  {"absolute", TRPositionAbsolute}, {NULL, 0}};
static const TRKeyword kDirection[] = {
  {"ltr", TRDirectionLTR}, {"rtl", TRDirectionRTL},
  {"inherit", TRDirectionInherit}, {NULL, 0}};
static const TRKeyword kFlexDirection[] = {
  {"row", TRFlexDirectionRow}, {"row-reverse", TRFlexDirectionRowReverse},
  {"column", TRFlexDirectionColumn},
  {"column-reverse", TRFlexDirectionColumnReverse}, {NULL, 0}};
static const TRKeyword kFlexWrap[] = {
  {"nowrap", TRFlexWrapNoWrap}, {"wrap", TRFlexWrapWrap},
  {"wrap-reverse", TRFlexWrapWrapReverse}, {NULL, 0}};
static const TRKeyword kAlign[] = {
  {"auto", TRAlignAuto}, {"normal", TRAlignNormal},
  {"flex-start", TRAlignFlexStart}, {"flex-end", TRAlignFlexEnd},
  {"start", TRAlignStart}, {"end", TRAlignEnd},
  {"self-start", TRAlignStart}, {"self-end", TRAlignEnd},
  {"center", TRAlignCenter}, {"stretch", TRAlignStretch},
  {"baseline", TRAlignBaseline}, {"first baseline", TRAlignBaseline},
  {"last baseline", TRAlignLastBaseline},
  {"space-between", TRAlignSpaceBetween},
  {"space-around", TRAlignSpaceAround},
  {"space-evenly", TRAlignSpaceEvenly}, {NULL, 0}};
/* justify-* also accept the physical left/right. */
static const TRKeyword kJustify[] = {
  {"auto", TRAlignAuto}, {"normal", TRAlignNormal},
  {"flex-start", TRAlignFlexStart}, {"flex-end", TRAlignFlexEnd},
  {"start", TRAlignStart}, {"end", TRAlignEnd},
  {"self-start", TRAlignStart}, {"self-end", TRAlignEnd},
  {"left", TRAlignLeft}, {"right", TRAlignRight},
  {"center", TRAlignCenter}, {"stretch", TRAlignStretch},
  {"baseline", TRAlignBaseline}, {"first baseline", TRAlignBaseline},
  {"space-between", TRAlignSpaceBetween},
  {"space-around", TRAlignSpaceAround},
  {"space-evenly", TRAlignSpaceEvenly}, {NULL, 0}};
static const TRKeyword kOverflow[] = {
  {"visible", TROverflowVisible}, {"hidden", TROverflowHidden},
  {"clip", TROverflowHidden}, {"scroll", TROverflowScroll},
  {"auto", TROverflowAuto}, {NULL, 0}};
static const TRKeyword kBoxSizing[] = {
  {"content-box", TRBoxSizingContentBox},
  {"border-box", TRBoxSizingBorderBox}, {NULL, 0}};

/* Declarations that are not layout but are understood by the view layer.
   Anything else is an error, so typos surface immediately. */
static NSSet *TRVisualProperties(void)
{
  static NSSet *set;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    set = [NSSet setWithObjects:
      @"background", @"background-color", @"color", @"opacity",
      @"font", @"font-family", @"font-size", @"font-weight", @"font-style",
      @"line-height", @"text-align", @"white-space", @"text-overflow",
      @"border-color", @"border-style", @"border-radius",
      @"border-top-color", @"border-right-color", @"border-bottom-color",
      @"border-left-color", @"box-shadow", @"visibility", @"z-index",
      @"cursor", @"content", @"container-type", @"container-name", nil];
  });
  return set;
}

/* Expands a 1-4 value box shorthand into left/top/right/bottom. */
static BOOL TRParseBox(NSString *value, TRValue out[4], BOOL allowAuto)
{
  NSArray *t = TRTokens(value);
  TRValue v[4];
  NSUInteger n = [t count];
  if (n < 1 || n > 4) return NO;
  for (NSUInteger i = 0; i < n; i++)
    if (!TRParseLength(t[i], &v[i], allowAuto, NO)) return NO;
  TRValue top = v[0];
  TRValue right = n > 1 ? v[1] : v[0];
  TRValue bottom = n > 2 ? v[2] : v[0];
  TRValue left = n > 3 ? v[3] : right;
  out[TREdgeTop] = top; out[TREdgeRight] = right;
  out[TREdgeBottom] = bottom; out[TREdgeLeft] = left;
  return YES;
}

static int TREdgeFromSuffix(NSString *suffix)
{
  if ([suffix isEqualToString: @"left"]) return TREdgeLeft;
  if ([suffix isEqualToString: @"top"]) return TREdgeTop;
  if ([suffix isEqualToString: @"right"]) return TREdgeRight;
  if ([suffix isEqualToString: @"bottom"]) return TREdgeBottom;
  /* Logical properties, horizontal-tb + ltr only for now. */
  if ([suffix isEqualToString: @"inline-start"]) return TREdgeLeft;
  if ([suffix isEqualToString: @"inline-end"]) return TREdgeRight;
  if ([suffix isEqualToString: @"block-start"]) return TREdgeTop;
  if ([suffix isEqualToString: @"block-end"]) return TREdgeBottom;
  return -1;
}

/* ------------------------------------------------------------------ */

@implementation TRStyle
{
  NSMutableDictionary<NSString *, NSString *> *_other;
}

@synthesize owner = _owner;

+ (instancetype)style
{
  return [[self alloc] init];
}

+ (instancetype)styleWithDeclarations:(NSString *)declarations
{
  return [self styleWithDeclarations: declarations error: NULL];
}

+ (instancetype)styleWithDeclarations:(NSString *)declarations error:(NSError **)error
{
  TRStyle *s = [[self alloc] init];
  if (![s applyDeclarations: declarations error: error]) return nil;
  return s;
}

+ (instancetype)styleWithDictionary:(NSDictionary *)dict error:(NSError **)error
{
  TRStyle *s = [[self alloc] init];
  if (![s applyDictionary: dict error: error]) return nil;
  return s;
}

- (instancetype)init
{
  if ((self = [super init]) != nil)
    {
      _s = TRStyleStorageInitial();
      _other = [NSMutableDictionary dictionary];
    }
  return self;
}

- (id)copyWithZone:(NSZone *)zone
{
  TRStyle *c = [[[self class] allocWithZone: zone] init];
  c->_s = _s;
  c->_other = [_other mutableCopy];
  c->_gridTemplateColumns = _gridTemplateColumns;
  c->_gridTemplateRows = _gridTemplateRows;
  c->_gridAutoColumns = _gridAutoColumns;
  c->_gridAutoRows = _gridAutoRows;
  c->_gridTemplateAreas = _gridTemplateAreas;
  c->_gridRowStart = _gridRowStart;
  c->_gridRowEnd = _gridRowEnd;
  c->_gridColumnStart = _gridColumnStart;
  c->_gridColumnEnd = _gridColumnEnd;
  return c;
}

- (NSDictionary *)otherDeclarations
{
  return [_other copy];
}

- (void)changed
{
  [_owner markDirty];
}

- (BOOL)applyDeclarations:(NSString *)declarations error:(NSError **)error
{
  for (NSString *decl in [declarations componentsSeparatedByString: @";"])
    {
      NSString *d = [decl stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([d length] == 0) continue;
      NSRange colon = [d rangeOfString: @":"];
      if (colon.location == NSNotFound)
        {
          if (error) *error = TRError(@"expected 'property: value' in \"%@\"", d);
          return NO;
        }
      NSString *prop = [[d substringToIndex: colon.location]
        stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
      NSString *val = [[d substringFromIndex: NSMaxRange(colon)]
        stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
      if ([val hasSuffix: @"!important"])
        val = [[val substringToIndex: [val length] - 10]
          stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
      if (![self setValue: val forProperty: prop error: error]) return NO;
    }
  return YES;
}

- (BOOL)applyDictionary:(NSDictionary *)dict error:(NSError **)error
{
  for (NSString *key in dict)
    if (![self setValue: dict[key] forProperty: key error: error]) return NO;
  return YES;
}

- (BOOL)setValue:(id)value forProperty:(NSString *)property error:(NSError **)error
{
  NSString *p = TRKebab(property);
  NSString *sv = [value isKindOfClass: [NSString class]]
    ? [(NSString *)value stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]]
    : [value description];
  BOOL ok = [self _set: p value: value string: sv];
  if (!ok)
    {
      if (error)
        {
          BOOL known = [self _isKnownProperty: p];
          *error = known
            ? TRError(@"invalid value \"%@\" for %@", sv, p)
            : TRError(@"unknown property \"%@\"", property);
        }
      return NO;
    }
  [self changed];
  return YES;
}

- (BOOL)_isKnownProperty:(NSString *)p
{
  static NSSet *layout;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    layout = [NSSet setWithObjects: @"display", @"position", @"direction",
      @"flex-direction", @"flex-wrap", @"flex-flow", @"justify-content",
      @"align-items", @"align-self", @"align-content", @"place-content",
      @"place-items", @"place-self", @"overflow", @"box-sizing", @"flex",
      @"flex-grow", @"flex-shrink", @"flex-basis", @"width", @"height",
      @"min-width", @"min-height", @"max-width", @"max-height",
      @"aspect-ratio", @"margin", @"padding", @"border", @"border-width",
      @"inset", @"gap", @"row-gap", @"column-gap", @"order", @"left",
      @"top", @"right", @"bottom", @"grid-template-columns", @"grid-template-rows",
      @"grid-template-areas", @"grid-auto-columns", @"grid-auto-rows", @"grid-auto-flow",
      @"grid-row", @"grid-column", @"grid-area", @"grid-row-start", @"grid-row-end",
      @"grid-column-start", @"grid-column-end", @"justify-items", @"justify-self",
      @"place-items", @"place-self", nil];
  });
  return [layout containsObject: p];
}

/* Sets one kebab-case property. Returns NO on an invalid value or an
   unknown property. */
- (BOOL)_set:(NSString *)p value:(id)obj string:(NSString *)v
{
  int k;
  TRValue len;
  TRFloat f;

#define KEYWORD(NAME, TABLE, FIELD, TYPE) \
  if ([p isEqualToString: NAME]) { \
    if (!TRLookup(v, TABLE, &k)) return NO; \
    _s.FIELD = (TYPE)k; return YES; }
#define LENGTH(NAME, FIELD, AUTO, NONE) \
  if ([p isEqualToString: NAME]) { \
    if (!TRValueFromObject(obj, &len, AUTO, NONE)) return NO; \
    _s.FIELD = len; return YES; }

  KEYWORD(@"display", kDisplay, display, TRDisplay)
  KEYWORD(@"position", kPosition, position, TRPosition)
  KEYWORD(@"direction", kDirection, direction, TRDirection)
  KEYWORD(@"flex-direction", kFlexDirection, flexDirection, TRFlexDirection)
  KEYWORD(@"flex-wrap", kFlexWrap, flexWrap, TRFlexWrap)
  if ([p isEqualToString: @"justify-content"] || [p isEqualToString: @"align-content"])
    {
      /* An optional safe/unsafe prefix; unsafe is the default behaviour. */
      BOOL safe = NO;
      NSString *kw = v;
      if ([kw hasPrefix: @"safe "]) { safe = YES; kw = [[kw substringFromIndex: 5] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]]; }
      else if ([kw hasPrefix: @"unsafe "]) kw = [[kw substringFromIndex: 7] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
      BOOL justify = [p isEqualToString: @"justify-content"];
      if (!TRLookup(kw, justify ? kJustify : kAlign, &k)) return NO;
      if (justify) { _s.justifyContent = (TRAlign)k; _s.justifyContentSafe = safe; }
      else { _s.alignContent = (TRAlign)k; _s.alignContentSafe = safe; }
      return YES;
    }
  KEYWORD(@"align-items", kAlign, alignItems, TRAlign)
  KEYWORD(@"align-self", kAlign, alignSelf, TRAlign)
  KEYWORD(@"overflow", kOverflow, overflow, TROverflow)
  KEYWORD(@"box-sizing", kBoxSizing, boxSizing, TRBoxSizing)
  LENGTH(@"width", width, YES, NO)
  LENGTH(@"height", height, YES, NO)
  LENGTH(@"min-width", minWidth, YES, NO)
  LENGTH(@"min-height", minHeight, YES, NO)
  LENGTH(@"max-width", maxWidth, NO, YES)
  LENGTH(@"max-height", maxHeight, NO, YES)
  LENGTH(@"flex-basis", flexBasis, YES, NO)
  /* gap's "normal" is 0 for flex and grid containers. */
  if (([p isEqualToString: @"row-gap"] || [p isEqualToString: @"column-gap"])
      && [v isKindOfClass: [NSString class]]
      && [[[v lowercaseString] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]] isEqualToString: @"normal"])
    {
      if ([p isEqualToString: @"row-gap"]) _s.rowGap = TRPx(0); else _s.columnGap = TRPx(0);
      return YES;
    }
  LENGTH(@"row-gap", rowGap, NO, NO)
  LENGTH(@"column-gap", columnGap, NO, NO)
#undef KEYWORD
#undef LENGTH

  if ([p isEqualToString: @"flex-basis"] && [[v lowercaseString] isEqualToString: @"content"])
    { _s.flexBasis = TRAuto; return YES; }
  if ([p isEqualToString: @"flex-grow"] || [p isEqualToString: @"flex-shrink"])
    {
      if (!TRParseNumber(v, &f) || f < 0) return NO;
      if ([p isEqualToString: @"flex-grow"]) _s.flexGrow = f; else _s.flexShrink = f;
      return YES;
    }
  if ([p isEqualToString: @"order"])
    {
      if (!TRParseNumber(v, &f)) return NO;
      _s.order = (NSInteger)f;
      return YES;
    }
  if ([p isEqualToString: @"aspect-ratio"])
    {
      NSString *t = [v stringByReplacingOccurrencesOfString: @" " withString: @""];
      if ([t isEqualToString: @"auto"]) { _s.aspectRatio = TRUndefined; _s.aspectRatioAuto = NO; return YES; }
      /* auto && <ratio>, in either order. */
      BOOL withAuto = NO;
      if ([t hasPrefix: @"auto"]) { withAuto = YES; t = [t substringFromIndex: 4]; }
      else if ([t hasSuffix: @"auto"]) { withAuto = YES; t = [t substringToIndex: [t length] - 4]; }
      NSArray *parts = [t componentsSeparatedByString: @"/"];
      TRFloat a, b = 1;
      if (!TRParseNumber(parts[0], &a)) return NO;
      if ([parts count] == 2 && !TRParseNumber(parts[1], &b)) return NO;
      if ([parts count] > 2 || a < 0 || b < 0) return NO;
      /* A degenerate ratio (0, or x/0) behaves as auto (CSS Values 4). */
      _s.aspectRatio = (a == 0 || b == 0) ? TRUndefined : a / b;
      _s.aspectRatioAuto = withAuto;
      return YES;
    }
  if ([p isEqualToString: @"gap"])
    {
      NSArray *t = TRTokens(v);
      TRValue r, c;
      if ([t count] < 1 || [t count] > 2) return NO;
      BOOL (^gapLen)(NSString *, TRValue *) = ^BOOL(NSString *tok, TRValue *out) {
        if ([[tok lowercaseString] isEqualToString: @"normal"]) { *out = TRPx(0); return YES; }
        return TRParseLength(tok, out, NO, NO);
      };
      if (!gapLen(t[0], &r)) return NO;
      c = r;
      if ([t count] == 2 && !gapLen(t[1], &c)) return NO;
      _s.rowGap = r; _s.columnGap = c;
      return YES;
    }
  if ([p isEqualToString: @"flex"])
    return [self _setFlexShorthand: v];
  if ([p hasPrefix: @"grid"] || [p isEqualToString: @"justify-items"] || [p isEqualToString: @"justify-self"])
    {
      int r = [self _setGrid: p value: v];
      if (r >= 0) return r == 1;
    }
  if ([p isEqualToString: @"flex-flow"])
    {
      for (NSString *t in TRTokens(v))
        {
          if (TRLookup(t, kFlexDirection, &k)) _s.flexDirection = (TRFlexDirection)k;
          else if (TRLookup(t, kFlexWrap, &k)) _s.flexWrap = (TRFlexWrap)k;
          else return NO;
        }
      return YES;
    }
  if ([p hasPrefix: @"place-"])
    {
      NSArray *t = TRTokens(v);
      int a, b;
      if ([t count] < 1 || [t count] > 2) return NO;
      if (!TRLookup(t[0], kAlign, &a)) return NO;
      b = a;
      if ([t count] == 2 && !TRLookup(t[1], kJustify, &b)) return NO;
      if ([p isEqualToString: @"place-content"])
        { _s.alignContent = (TRAlign)a; _s.justifyContent = (TRAlign)b; return YES; }
      if ([p isEqualToString: @"place-items"])
        { _s.alignItems = (TRAlign)a; _s.justifyItems = (TRAlign)b; return YES; }
      if ([p isEqualToString: @"place-self"])
        { _s.alignSelf = (TRAlign)a; _s.justifySelf = (TRAlign)b; return YES; }
      return NO;
    }
  if ([p isEqualToString: @"margin"])
    return TRParseBox(v, _s.margin, YES);
  if ([p isEqualToString: @"padding"])
    return TRParseBox(v, _s.padding, NO);
  if ([p isEqualToString: @"border-width"])
    return TRParseBox(v, _s.border, NO);
  if ([p isEqualToString: @"inset"])
    return TRParseBox(v, _s.inset, YES);
  if ([p isEqualToString: @"left"] || [p isEqualToString: @"top"]
      || [p isEqualToString: @"right"] || [p isEqualToString: @"bottom"])
    {
      if (!TRValueFromObject(obj, &len, YES, NO)) return NO;
      _s.inset[TREdgeFromSuffix(p)] = len;
      return YES;
    }
  if ([p hasPrefix: @"margin-"] || [p hasPrefix: @"padding-"] || [p hasPrefix: @"inset-"])
    {
      NSRange dash = [p rangeOfString: @"-"];
      NSString *base = [p substringToIndex: dash.location];
      int e = TREdgeFromSuffix([p substringFromIndex: NSMaxRange(dash)]);
      if (e < 0) return NO;
      BOOL allowAuto = ![base isEqualToString: @"padding"];
      if (!TRValueFromObject(obj, &len, allowAuto, NO)) return NO;
      if ([base isEqualToString: @"margin"]) _s.margin[e] = len;
      else if ([base isEqualToString: @"padding"]) _s.padding[e] = len;
      else _s.inset[e] = len;
      return YES;
    }
  if ([p hasPrefix: @"border-"] && [p hasSuffix: @"-width"])
    {
      NSString *mid = [p substringWithRange: NSMakeRange(7, [p length] - 13)];
      int e = TREdgeFromSuffix(mid);
      if (e < 0) return NO;
      if (!TRValueFromObject(obj, &len, NO, NO)) return NO;
      _s.border[e] = len;
      return YES;
    }
  if ([p isEqualToString: @"border"])
    {
      /* border: <width> || <style> || <color>; only the width is layout. */
      static NSSet *styles;
      static dispatch_once_t once;
      dispatch_once(&once, ^{
        styles = [NSSet setWithObjects: @"none", @"hidden", @"solid", @"dashed",
          @"dotted", @"double", @"groove", @"ridge", @"inset", @"outset", nil];
      });
      TRValue w = TRPx(0);
      BOOL sawWidth = NO;
      for (NSString *t in TRTokens(v))
        {
          if (!sawWidth && TRParseLength(t, &len, NO, NO)) { w = len; sawWidth = YES; }
          else if ([styles containsObject: [t lowercaseString]])
            _other[@"border-style"] = t;
          else
            _other[@"border-color"] = t;
        }
      if (!sawWidth && _other[@"border-style"] != nil
          && ![_other[@"border-style"] isEqualToString: @"none"])
        w = TRPx(3);   /* CSS 'medium' */
      for (int i = 0; i < 4; i++) _s.border[i] = w;
      return YES;
    }
  if ([TRVisualProperties() containsObject: p] || [p hasPrefix: @"--"]
      || [p hasPrefix: @"-trellis-"])
    {
      _other[p] = v;
      return YES;
    }
  return NO;
}

/* Grid properties. Returns 1 = set, 0 = invalid value, -1 = not a grid property. */
- (int)_setGrid:(NSString *)p value:(NSString *)v
{
  int k;
  if ([p isEqualToString: @"justify-items"] || [p isEqualToString: @"justify-self"])
    {
      if (!TRLookup(v, kJustify, &k)) return 0;
      if ([p isEqualToString: @"justify-items"]) _s.justifyItems = (TRAlign)k; else _s.justifySelf = (TRAlign)k;
      return 1;
    }
  if ([p isEqualToString: @"grid-template-columns"] || [p isEqualToString: @"grid-template-rows"]
      || [p isEqualToString: @"grid-auto-columns"] || [p isEqualToString: @"grid-auto-rows"])
    {
      BOOL isAuto = [p hasPrefix: @"grid-auto"];
      NSString *val = [[v lowercaseString] isEqualToString: @"none"] ? nil : v;
      if (val && !TRGridValidateTrackList(val, isAuto)) return 0;
      if ([p isEqualToString: @"grid-template-columns"]) _gridTemplateColumns = val;
      else if ([p isEqualToString: @"grid-template-rows"]) _gridTemplateRows = val;
      else if ([p isEqualToString: @"grid-auto-columns"]) _gridAutoColumns = val;
      else _gridAutoRows = val;
      return 1;
    }
  if ([p isEqualToString: @"grid-template-areas"])
    {
      if ([[v lowercaseString] isEqualToString: @"none"]) { _gridTemplateAreas = nil; return 1; }
      NSArray *areas = TRGridParseAreas(v);
      if (areas == nil) return 0;
      _gridTemplateAreas = areas;
      return 1;
    }
  if ([p isEqualToString: @"grid-auto-flow"])
    {
      /* [row | column] || dense */
      BOOL column = NO, dense = NO, sawAxis = NO;
      for (NSString *t in [[v lowercaseString] componentsSeparatedByCharactersInSet: [NSCharacterSet whitespaceCharacterSet]])
        {
          if ([t length] == 0) continue;
          if ([t isEqualToString: @"dense"] && !dense) dense = YES;
          else if (([t isEqualToString: @"row"] || [t isEqualToString: @"column"]) && !sawAxis)
            { sawAxis = YES; column = [t isEqualToString: @"column"]; }
          else return 0;
        }
      if (!sawAxis && !dense) return 0;
      _s.gridAutoFlowColumn = column;
      _s.gridAutoFlowDense = dense;
      return 1;
    }
  if ([p isEqualToString: @"grid-row-start"] || [p isEqualToString: @"grid-row-end"]
      || [p isEqualToString: @"grid-column-start"] || [p isEqualToString: @"grid-column-end"])
    {
      if (!TRGridValidateLine(v)) return 0;
      if ([p isEqualToString: @"grid-row-start"]) _gridRowStart = v;
      else if ([p isEqualToString: @"grid-row-end"]) _gridRowEnd = v;
      else if ([p isEqualToString: @"grid-column-start"]) _gridColumnStart = v;
      else _gridColumnEnd = v;
      return 1;
    }
  if ([p isEqualToString: @"grid-row"] || [p isEqualToString: @"grid-column"])
    {
      NSArray *parts = [v componentsSeparatedByString: @"/"];
      if ([parts count] > 2) return 0;
      NSString *a = [parts[0] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
      NSString *b = [parts count] == 2
        ? [parts[1] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]] : nil;
      if (!TRGridValidateLine(a) || (b && !TRGridValidateLine(b))) return 0;
      /* A lone area/line name means name / name (CSS); otherwise auto. */
      if (b == nil) b = TRGridIsName(a) ? a : @"auto";
      if ([p isEqualToString: @"grid-row"]) { _gridRowStart = a; _gridRowEnd = b; }
      else { _gridColumnStart = a; _gridColumnEnd = b; }
      return 1;
    }
  if ([p isEqualToString: @"grid-area"])
    {
      NSMutableArray *parts = [NSMutableArray array];
      for (NSString *x in [v componentsSeparatedByString: @"/"])
        [parts addObject: [x stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]]];
      if ([parts count] < 1 || [parts count] > 4) return 0;
      for (NSString *x in parts) if (!TRGridValidateLine(x)) return 0;
      NSString *rs = parts[0];
      NSString *cs = [parts count] > 1 ? parts[1] : (TRGridIsName(rs) ? rs : @"auto");
      NSString *re = [parts count] > 2 ? parts[2] : (TRGridIsName(rs) ? rs : @"auto");
      NSString *ce = [parts count] > 3 ? parts[3] : (TRGridIsName(cs) ? cs : @"auto");
      _gridRowStart = rs; _gridColumnStart = cs; _gridRowEnd = re; _gridColumnEnd = ce;
      return 1;
    }
  return -1;
}

- (BOOL)_setFlexShorthand:(NSString *)v
{
  NSString *lv = [v lowercaseString];
  if ([lv isEqualToString: @"none"])
    { _s.flexGrow = 0; _s.flexShrink = 0; _s.flexBasis = TRAuto; return YES; }
  if ([lv isEqualToString: @"auto"])
    { _s.flexGrow = 1; _s.flexShrink = 1; _s.flexBasis = TRAuto; return YES; }
  if ([lv isEqualToString: @"initial"])
    { _s.flexGrow = 0; _s.flexShrink = 1; _s.flexBasis = TRAuto; return YES; }
  NSArray *t = TRTokens(v);
  if ([t count] < 1 || [t count] > 3) return NO;
  TRFloat nums[2];
  int nn = 0;
  TRValue basis = TRPercent(0);   /* omitted basis in the shorthand is 0 */
  BOOL sawBasis = NO;
  for (NSString *tok in t)
    {
      TRFloat f;
      if (nn < 2 && !sawBasis && TRParseNumber(tok, &f))
        { nums[nn++] = f; continue; }
      if (nn < 2 && sawBasis && TRParseNumber(tok, &f) && nn == 0)
        { nums[nn++] = f; continue; }
      if (!sawBasis && (TRParseLength(tok, &basis, YES, NO)
                        || [[tok lowercaseString] isEqualToString: @"content"]))
        {
          if ([[tok lowercaseString] isEqualToString: @"content"]) basis = TRAuto;
          sawBasis = YES;
          continue;
        }
      if (nn < 2 && TRParseNumber(tok, &f)) { nums[nn++] = f; continue; }
      return NO;
    }
  _s.flexGrow = nn > 0 ? nums[0] : 1;
  _s.flexShrink = nn > 1 ? nums[1] : 1;
  _s.flexBasis = basis;
  return YES;
}

/* ------------------------------------------------------------------ */
#pragma mark Typed accessors

#define ACCESSOR(TYPE, GETTER, SETTER, FIELD) \
  - (TYPE)GETTER { return _s.FIELD; } \
  - (void)SETTER:(TYPE)v { _s.FIELD = v; [self changed]; }

ACCESSOR(TRDisplay, display, setDisplay, display)
ACCESSOR(TRPosition, position, setPosition, position)
ACCESSOR(TRDirection, direction, setDirection, direction)
ACCESSOR(TRFlexDirection, flexDirection, setFlexDirection, flexDirection)
ACCESSOR(TRFlexWrap, flexWrap, setFlexWrap, flexWrap)
ACCESSOR(TRAlign, justifyContent, setJustifyContent, justifyContent)
ACCESSOR(TRAlign, alignItems, setAlignItems, alignItems)
ACCESSOR(TRAlign, alignSelf, setAlignSelf, alignSelf)
ACCESSOR(TRAlign, alignContent, setAlignContent, alignContent)
ACCESSOR(TROverflow, overflow, setOverflow, overflow)
ACCESSOR(TRBoxSizing, boxSizing, setBoxSizing, boxSizing)
ACCESSOR(TRFloat, flexGrow, setFlexGrow, flexGrow)
ACCESSOR(TRFloat, flexShrink, setFlexShrink, flexShrink)
ACCESSOR(TRValue, flexBasis, setFlexBasis, flexBasis)
ACCESSOR(TRValue, width, setWidth, width)
ACCESSOR(TRValue, height, setHeight, height)
ACCESSOR(TRValue, minWidth, setMinWidth, minWidth)
ACCESSOR(TRValue, minHeight, setMinHeight, minHeight)
ACCESSOR(TRValue, maxWidth, setMaxWidth, maxWidth)
ACCESSOR(TRValue, maxHeight, setMaxHeight, maxHeight)
ACCESSOR(TRFloat, aspectRatio, setAspectRatio, aspectRatio)
ACCESSOR(TRValue, rowGap, setRowGap, rowGap)
ACCESSOR(TRValue, columnGap, setColumnGap, columnGap)
ACCESSOR(NSInteger, order, setOrder, order)
#undef ACCESSOR

- (TRValue)marginForEdge:(TREdge)e { return _s.margin[e]; }
- (void)setMargin:(TRValue)v forEdge:(TREdge)e { _s.margin[e] = v; [self changed]; }
- (TRValue)paddingForEdge:(TREdge)e { return _s.padding[e]; }
- (void)setPadding:(TRValue)v forEdge:(TREdge)e { _s.padding[e] = v; [self changed]; }
- (TRValue)borderWidthForEdge:(TREdge)e { return _s.border[e]; }
- (void)setBorderWidth:(TRValue)v forEdge:(TREdge)e { _s.border[e] = v; [self changed]; }
- (TRValue)insetForEdge:(TREdge)e { return _s.inset[e]; }
- (void)setInset:(TRValue)v forEdge:(TREdge)e { _s.inset[e] = v; [self changed]; }
- (void)setMargin:(TRValue)v { for (int i = 0; i < 4; i++) _s.margin[i] = v; [self changed]; }
- (void)setPadding:(TRValue)v { for (int i = 0; i < 4; i++) _s.padding[i] = v; [self changed]; }
- (void)setGap:(TRValue)v { _s.rowGap = _s.columnGap = v; [self changed]; }

/* ------------------------------------------------------------------ */
#pragma mark Serialisation

static NSString *TRValueString(TRValue v)
{
  switch (v.unit)
    {
      case TRUnitAuto: return @"auto";
      case TRUnitUndefined: return @"none";
      case TRUnitPercent: return [NSString stringWithFormat: @"%g%%", v.value];
      case TRUnitPoint: return [NSString stringWithFormat: @"%gpx", v.value];
    }
  return @"";
}

static NSString *TRKeywordString(const TRKeyword *table, int value)
{
  for (const TRKeyword *k = table; k->name; k++)
    if (k->value == value) return [NSString stringWithUTF8String: k->name];
  return @"?";
}

- (NSString *)declarationString
{
  TRStyleStorage d = TRStyleStorageInitial();
  NSMutableArray *out = [NSMutableArray array];
#define KW(NAME, TABLE, FIELD) \
  if (_s.FIELD != d.FIELD) [out addObject: [NSString stringWithFormat: @"%@: %@", NAME, TRKeywordString(TABLE, _s.FIELD)]];
#define LEN(NAME, FIELD) \
  if (!TRValueEqual(_s.FIELD, d.FIELD)) [out addObject: [NSString stringWithFormat: @"%@: %@", NAME, TRValueString(_s.FIELD)]];
  KW(@"display", kDisplay, display)
  KW(@"position", kPosition, position)
  KW(@"direction", kDirection, direction)
  KW(@"flex-direction", kFlexDirection, flexDirection)
  KW(@"flex-wrap", kFlexWrap, flexWrap)
  if (_s.justifyContent != d.justifyContent || _s.justifyContentSafe)
    [out addObject: [NSString stringWithFormat: @"justify-content: %@%@", _s.justifyContentSafe ? @"safe " : @"",
                     TRKeywordString(kJustify, _s.justifyContent)]];
  KW(@"align-items", kAlign, alignItems)
  KW(@"align-self", kAlign, alignSelf)
  if (_s.alignContent != d.alignContent || _s.alignContentSafe)
    [out addObject: [NSString stringWithFormat: @"align-content: %@%@", _s.alignContentSafe ? @"safe " : @"",
                     TRKeywordString(kAlign, _s.alignContent)]];
  KW(@"overflow", kOverflow, overflow)
  KW(@"box-sizing", kBoxSizing, boxSizing)
  if (_s.flexGrow != d.flexGrow) [out addObject: [NSString stringWithFormat: @"flex-grow: %g", _s.flexGrow]];
  if (_s.flexShrink != d.flexShrink) [out addObject: [NSString stringWithFormat: @"flex-shrink: %g", _s.flexShrink]];
  LEN(@"flex-basis", flexBasis)
  LEN(@"width", width)
  LEN(@"height", height)
  LEN(@"min-width", minWidth)
  LEN(@"min-height", minHeight)
  LEN(@"max-width", maxWidth)
  LEN(@"max-height", maxHeight)
  if (TRIsDefined(_s.aspectRatio)) [out addObject: [NSString stringWithFormat: @"aspect-ratio: %@%g", _s.aspectRatioAuto ? @"auto " : @"", _s.aspectRatio]];
  static NSString *edges[4] = { @"left", @"top", @"right", @"bottom" };
  for (int i = 0; i < 4; i++)
    {
      LEN(([NSString stringWithFormat: @"margin-%@", edges[i]]), margin[i])
      LEN(([NSString stringWithFormat: @"padding-%@", edges[i]]), padding[i])
      LEN(([NSString stringWithFormat: @"border-%@-width", edges[i]]), border[i])
      LEN(edges[i], inset[i])
    }
  LEN(@"row-gap", rowGap)
  LEN(@"column-gap", columnGap)
  if (_s.order != 0) [out addObject: [NSString stringWithFormat: @"order: %ld", (long)_s.order]];
  KW(@"justify-items", kJustify, justifyItems)
  KW(@"justify-self", kJustify, justifySelf)
  if (_s.gridAutoFlowColumn || _s.gridAutoFlowDense)
    [out addObject: [NSString stringWithFormat: @"grid-auto-flow: %@%@",
                     _s.gridAutoFlowColumn ? @"column" : @"row", _s.gridAutoFlowDense ? @" dense" : @""]];
  if (_gridTemplateColumns) [out addObject: [@"grid-template-columns: " stringByAppendingString: _gridTemplateColumns]];
  if (_gridTemplateRows) [out addObject: [@"grid-template-rows: " stringByAppendingString: _gridTemplateRows]];
  if (_gridAutoColumns) [out addObject: [@"grid-auto-columns: " stringByAppendingString: _gridAutoColumns]];
  if (_gridAutoRows) [out addObject: [@"grid-auto-rows: " stringByAppendingString: _gridAutoRows]];
  if (_gridTemplateAreas)
    {
      NSMutableArray *rows = [NSMutableArray array];
      for (NSArray *r in _gridTemplateAreas)
        [rows addObject: [NSString stringWithFormat: @"\"%@\"", [r componentsJoinedByString: @" "]]];
      [out addObject: [@"grid-template-areas: " stringByAppendingString: [rows componentsJoinedByString: @" "]]];
    }
  if (_gridRowStart || _gridRowEnd)
    [out addObject: [NSString stringWithFormat: @"grid-row: %@ / %@", _gridRowStart ?: @"auto", _gridRowEnd ?: @"auto"]];
  if (_gridColumnStart || _gridColumnEnd)
    [out addObject: [NSString stringWithFormat: @"grid-column: %@ / %@", _gridColumnStart ?: @"auto", _gridColumnEnd ?: @"auto"]];
#undef KW
#undef LEN
  for (NSString *k in [[_other allKeys] sortedArrayUsingSelector: @selector(compare:)])
    [out addObject: [NSString stringWithFormat: @"%@: %@", k, _other[k]]];
  return [out componentsJoinedByString: @"; "];
}

- (NSString *)description
{
  return [NSString stringWithFormat: @"<TRStyle %@>", [self declarationString]];
}

@end
