/* Reference engine adapter: runs conformance cases through Yoga.
 *
 * Copyright (C) 2026 Trellis contributors.  LGPL-2.1-or-later.
 *
 * Not part of Trellis.  It exists to validate the imported cases: the Yoga
 * suite should pass (nearly) completely on Yoga itself, and WPT results on
 * Yoga give a baseline for "a mature non-browser flexbox engine".
 * Build with `make -f Makefile.macos reference YOGA=/path/to/yoga`.
 */
#import "../TRConformance.h"
#include <yoga/Yoga.h>
#include <math.h>
#include <string>

static YGSize measureFunc(YGNodeConstRef node, float w, YGMeasureMode wm,
                          float h, YGMeasureMode hm)
{
  NSDictionary *m = (__bridge NSDictionary *)YGNodeGetContext(node);
  auto mode = [](YGMeasureMode x) { return x == YGMeasureModeExactly ? 1 : x == YGMeasureModeAtMost ? 2 : 0; };
  TRConfSize s = TRConfMeasure(m, w, mode(wm), h, mode(hm));
  return YGSize{(float)s.width, (float)s.height};
}

/* Value: NSNumber (px) or NSString ("10px", "50%", "auto", "max-content"). */
struct Val { enum { Px, Pct, Auto, Keyword, Bad } kind; float v; std::string kw; };

static Val parseVal(id o)
{
  if ([o isKindOfClass:[NSNumber class]]) return {Val::Px, [o floatValue], ""};
  NSString *s = [[o description] stringByTrimmingCharactersInSet:
                 [NSCharacterSet whitespaceCharacterSet]];
  if ([s isEqualToString:@"auto"]) return {Val::Auto, 0, ""};
  if ([s hasSuffix:@"%"]) return {Val::Pct, [[s substringToIndex:[s length] - 1] floatValue], ""};
  if ([s hasSuffix:@"px"]) s = [s substringToIndex:[s length] - 2];
  NSScanner *sc = [NSScanner scannerWithString:s];
  float f;
  if ([sc scanFloat:&f] && [sc isAtEnd]) return {Val::Px, f, ""};
  return {Val::Keyword, 0, std::string([s UTF8String])};
}

typedef void (*DimSet)(YGNodeRef, float);
static BOOL setDim(YGNodeRef n, Val v, DimSet px, DimSet pct, void (*autoF)(YGNodeRef),
                   void (*maxContent)(YGNodeRef), void (*stretch)(YGNodeRef), void (*fit)(YGNodeRef))
{
  switch (v.kind) {
    case Val::Px: px(n, v.v); return YES;
    case Val::Pct: pct(n, v.v); return YES;
    case Val::Auto: if (autoF) { autoF(n); return YES; } return NO;
    case Val::Keyword:
      if (v.kw == "max-content" && maxContent) { maxContent(n); return YES; }
      if (v.kw == "stretch" && stretch) { stretch(n); return YES; }
      if (v.kw == "fit-content" && fit) { fit(n); return YES; }
      if (v.kw == "none") return YES;     // max-width: none
      return NO;
    default: return NO;
  }
}

static NSDictionary *enumMap(void)
{
  static NSDictionary *m;
  if (!m) m = @{
    @"flexDirection": @{@"row": @(YGFlexDirectionRow), @"row-reverse": @(YGFlexDirectionRowReverse),
                        @"column": @(YGFlexDirectionColumn), @"column-reverse": @(YGFlexDirectionColumnReverse)},
    @"justifyContent": @{@"flex-start": @(YGJustifyFlexStart), @"start": @(YGJustifyFlexStart),
                         @"normal": @(YGJustifyFlexStart), @"left": @(YGJustifyFlexStart),
                         @"center": @(YGJustifyCenter), @"flex-end": @(YGJustifyFlexEnd),
                         @"end": @(YGJustifyFlexEnd), @"right": @(YGJustifyFlexEnd),
                         @"space-between": @(YGJustifySpaceBetween),
                         @"space-around": @(YGJustifySpaceAround), @"space-evenly": @(YGJustifySpaceEvenly)},
    @"align": @{@"auto": @(YGAlignAuto), @"flex-start": @(YGAlignFlexStart), @"start": @(YGAlignFlexStart),
                @"self-start": @(YGAlignFlexStart),
                @"center": @(YGAlignCenter), @"flex-end": @(YGAlignFlexEnd), @"end": @(YGAlignFlexEnd),
                @"self-end": @(YGAlignFlexEnd),
                @"stretch": @(YGAlignStretch), @"normal": @(YGAlignStretch), @"baseline": @(YGAlignBaseline),
                @"space-between": @(YGAlignSpaceBetween), @"space-around": @(YGAlignSpaceAround),
                @"space-evenly": @(YGAlignSpaceEvenly)},
    @"position": @{@"relative": @(YGPositionTypeRelative), @"absolute": @(YGPositionTypeAbsolute),
                   @"static": @(YGPositionTypeStatic)},
    @"flexWrap": @{@"nowrap": @(YGWrapNoWrap), @"wrap": @(YGWrapWrap), @"wrap-reverse": @(YGWrapWrapReverse)},
    @"overflow": @{@"visible": @(YGOverflowVisible), @"hidden": @(YGOverflowHidden),
                   @"scroll": @(YGOverflowScroll), @"auto": @(YGOverflowScroll), @"clip": @(YGOverflowHidden)},
    @"display": @{@"flex": @(YGDisplayFlex), @"none": @(YGDisplayNone), @"contents": @(YGDisplayContents),
                  @"block": @(YGDisplayFlex), @"inline-flex": @(YGDisplayFlex)},
    @"boxSizing": @{@"border-box": @(YGBoxSizingBorderBox), @"content-box": @(YGBoxSizingContentBox)},
  };
  return m;
}

static int enumFor(NSString *table, id value)
{
  NSNumber *n = enumMap()[table][[value description]];
  return n ? [n intValue] : -1;
}

static NSString *applyStyle(YGNodeRef n, NSDictionary *style)
{
  /* Trellis/CSS boxes default to content-box; Yoga to border-box. */
  YGNodeStyleSetBoxSizing(n, YGBoxSizingContentBox);
  for (NSString *k in style) {
    id o = style[k];
    Val v = parseVal(o);
    int e;
    if ([k isEqualToString:@"flexDirection"]) { if ((e = enumFor(@"flexDirection", o)) < 0) goto bad; YGNodeStyleSetFlexDirection(n, (YGFlexDirection)e); continue; }
    if ([k isEqualToString:@"justifyContent"]) { if ((e = enumFor(@"justifyContent", o)) < 0) goto bad; YGNodeStyleSetJustifyContent(n, (YGJustify)e); continue; }
    if ([k isEqualToString:@"alignItems"]) { if ((e = enumFor(@"align", o)) < 0) goto bad; YGNodeStyleSetAlignItems(n, (YGAlign)e); continue; }
    if ([k isEqualToString:@"alignSelf"]) { if ((e = enumFor(@"align", o)) < 0) goto bad; YGNodeStyleSetAlignSelf(n, (YGAlign)e); continue; }
    if ([k isEqualToString:@"alignContent"]) { if ((e = enumFor(@"align", o)) < 0) goto bad; YGNodeStyleSetAlignContent(n, (YGAlign)e); continue; }
    if ([k isEqualToString:@"position"]) { if ((e = enumFor(@"position", o)) < 0) goto bad; YGNodeStyleSetPositionType(n, (YGPositionType)e); continue; }
    if ([k isEqualToString:@"flexWrap"]) { if ((e = enumFor(@"flexWrap", o)) < 0) goto bad; YGNodeStyleSetFlexWrap(n, (YGWrap)e); continue; }
    if ([k isEqualToString:@"overflow"] || [k isEqualToString:@"overflowX"] || [k isEqualToString:@"overflowY"]) { if ((e = enumFor(@"overflow", o)) < 0) goto bad; YGNodeStyleSetOverflow(n, (YGOverflow)e); continue; }
    if ([k isEqualToString:@"display"]) { if ((e = enumFor(@"display", o)) < 0) goto bad; YGNodeStyleSetDisplay(n, (YGDisplay)e); continue; }
    if ([k isEqualToString:@"boxSizing"]) { if ((e = enumFor(@"boxSizing", o)) < 0) goto bad; YGNodeStyleSetBoxSizing(n, (YGBoxSizing)e); continue; }
    if ([k isEqualToString:@"flexGrow"]) { if (v.kind != Val::Px) goto bad; YGNodeStyleSetFlexGrow(n, v.v); continue; }
    if ([k isEqualToString:@"flexShrink"]) { if (v.kind != Val::Px) goto bad; YGNodeStyleSetFlexShrink(n, v.v); continue; }
    if ([k isEqualToString:@"aspectRatio"]) { if (v.kind != Val::Px) goto bad; YGNodeStyleSetAspectRatio(n, v.v); continue; }
    if ([k isEqualToString:@"flexBasis"]) { if (!setDim(n, v, YGNodeStyleSetFlexBasis, YGNodeStyleSetFlexBasisPercent, YGNodeStyleSetFlexBasisAuto, YGNodeStyleSetFlexBasisMaxContent, YGNodeStyleSetFlexBasisStretch, YGNodeStyleSetFlexBasisFitContent)) goto bad; continue; }
    if ([k isEqualToString:@"width"]) { if (!setDim(n, v, YGNodeStyleSetWidth, YGNodeStyleSetWidthPercent, YGNodeStyleSetWidthAuto, YGNodeStyleSetWidthMaxContent, YGNodeStyleSetWidthStretch, YGNodeStyleSetWidthFitContent)) goto bad; continue; }
    if ([k isEqualToString:@"height"]) { if (!setDim(n, v, YGNodeStyleSetHeight, YGNodeStyleSetHeightPercent, YGNodeStyleSetHeightAuto, YGNodeStyleSetHeightMaxContent, YGNodeStyleSetHeightStretch, YGNodeStyleSetHeightFitContent)) goto bad; continue; }
    if ([k isEqualToString:@"minWidth"]) { if (v.kind == Val::Auto) continue; if (!setDim(n, v, YGNodeStyleSetMinWidth, YGNodeStyleSetMinWidthPercent, NULL, YGNodeStyleSetMinWidthMaxContent, YGNodeStyleSetMinWidthStretch, YGNodeStyleSetMinWidthFitContent)) goto bad; continue; }
    if ([k isEqualToString:@"minHeight"]) { if (v.kind == Val::Auto) continue; if (!setDim(n, v, YGNodeStyleSetMinHeight, YGNodeStyleSetMinHeightPercent, NULL, YGNodeStyleSetMinHeightMaxContent, YGNodeStyleSetMinHeightStretch, YGNodeStyleSetMinHeightFitContent)) goto bad; continue; }
    if ([k isEqualToString:@"maxWidth"]) { if (!setDim(n, v, YGNodeStyleSetMaxWidth, YGNodeStyleSetMaxWidthPercent, NULL, YGNodeStyleSetMaxWidthMaxContent, YGNodeStyleSetMaxWidthStretch, YGNodeStyleSetMaxWidthFitContent)) goto bad; continue; }
    if ([k isEqualToString:@"maxHeight"]) { if (!setDim(n, v, YGNodeStyleSetMaxHeight, YGNodeStyleSetMaxHeightPercent, NULL, YGNodeStyleSetMaxHeightMaxContent, YGNodeStyleSetMaxHeightStretch, YGNodeStyleSetMaxHeightFitContent)) goto bad; continue; }
    if ([k isEqualToString:@"rowGap"] || [k isEqualToString:@"columnGap"]) {
      YGGutter g = [k isEqualToString:@"rowGap"] ? YGGutterRow : YGGutterColumn;
      if (v.kind == Val::Px) YGNodeStyleSetGap(n, g, v.v);
      else if (v.kind == Val::Pct) YGNodeStyleSetGapPercent(n, g, v.v);
      else if (v.kind == Val::Keyword && v.kw == "normal") ;
      else goto bad;
      continue;
    }
    {
      static NSDictionary *edges;
      if (!edges) edges = @{@"Left": @(YGEdgeLeft), @"Top": @(YGEdgeTop),
                            @"Right": @(YGEdgeRight), @"Bottom": @(YGEdgeBottom)};
      BOOL handled = NO;
      for (NSString *side in edges) {
        YGEdge edge = (YGEdge)[edges[side] intValue];
        NSString *lower = [side lowercaseString];
        if ([k isEqualToString:[@"margin" stringByAppendingString:side]]) {
          if (v.kind == Val::Px) YGNodeStyleSetMargin(n, edge, v.v);
          else if (v.kind == Val::Pct) YGNodeStyleSetMarginPercent(n, edge, v.v);
          else if (v.kind == Val::Auto) YGNodeStyleSetMarginAuto(n, edge);
          else goto bad;
          handled = YES; break;
        }
        if ([k isEqualToString:[@"padding" stringByAppendingString:side]]) {
          if (v.kind == Val::Px) YGNodeStyleSetPadding(n, edge, v.v);
          else if (v.kind == Val::Pct) YGNodeStyleSetPaddingPercent(n, edge, v.v);
          else goto bad;
          handled = YES; break;
        }
        if ([k isEqualToString:[NSString stringWithFormat:@"border%@Width", side]]) {
          if (v.kind != Val::Px) goto bad;
          YGNodeStyleSetBorder(n, edge, v.v);
          handled = YES; break;
        }
        if ([k isEqualToString:lower]) {
          if (v.kind == Val::Px) YGNodeStyleSetPosition(n, edge, v.v);
          else if (v.kind == Val::Pct) YGNodeStyleSetPositionPercent(n, edge, v.v);
          else if (v.kind == Val::Auto) YGNodeStyleSetPositionAuto(n, edge);
          else goto bad;
          handled = YES; break;
        }
      }
      if (handled) continue;
    }
    return [NSString stringWithFormat:@"unsupported property %@", k];
  bad:
    return [NSString stringWithFormat:@"unsupported value %@: %@", k, o];
  }
  return nil;
}

@interface TRConfEngineYoga : NSObject <TRConfEngine>
@end

@implementation TRConfEngineYoga
- (NSString *)engineName { return @"yoga"; }
- (NSSet *)unsupportedFeatures
{
  return [NSSet setWithObjects:@"block-layout", @"display-inline-block", @"display-inline",
          @"display-grid", @"grid", @"logical-properties", @"display--webkit-box", @"calc", nil];
}

static YGNodeRef build(NSDictionary *spec, YGConfigRef config, NSString **err)
{
  YGNodeRef n = YGNodeNewWithConfig(config);
  NSString *e = applyStyle(n, spec[@"style"]);
  if (e && err && !*err) *err = e;
  if (spec[@"measure"]) {
    YGNodeSetContext(n, (__bridge void *)spec[@"measure"]);
    YGNodeSetMeasureFunc(n, measureFunc);
  }
  NSArray *kids = spec[@"children"];
  for (NSUInteger i = 0; i < [kids count]; i++)
    YGNodeInsertChild(n, build(kids[i], config, err), i);
  return n;
}

static NSDictionary *frames(YGNodeRef n)
{
  NSMutableArray *kids = [NSMutableArray array];
  for (size_t i = 0; i < YGNodeGetChildCount(n); i++)
    [kids addObject:frames(YGNodeGetChild(n, i))];
  return @{@"x": @(YGNodeLayoutGetLeft(n)), @"y": @(YGNodeLayoutGetTop(n)),
           @"width": @(YGNodeLayoutGetWidth(n)), @"height": @(YGNodeLayoutGetHeight(n)),
           @"children": kids};
}

- (NSDictionary *)layoutCase:(NSDictionary *)c error:(NSString **)error
{
  YGConfigRef config = YGConfigNew();
  YGConfigSetUseWebDefaults(config, true);
  NSString *err = nil;
  YGNodeRef root = build(c[@"root"], config, &err);
  if (err) {
    YGNodeFreeRecursive(root);
    YGConfigFree(config);
    *error = err;
    return nil;
  }
  NSDictionary *avail = c[@"available"];
  float w = YGUndefined, h = YGUndefined;
  if ([avail[@"width"] isKindOfClass:[NSNumber class]] &&
      ![c[@"rootSizing"] isEqual:@"fit-content"])
    w = [avail[@"width"] floatValue];
  if ([avail[@"height"] isKindOfClass:[NSNumber class]])
    h = [avail[@"height"] floatValue];
  YGNodeCalculateLayout(root, w, h,
                        [c[@"direction"] isEqual:@"rtl"] ? YGDirectionRTL : YGDirectionLTR);
  NSDictionary *f = frames(root);
  YGNodeFreeRecursive(root);
  YGConfigFree(config);
  return f;
}
@end

int main(int argc, const char **argv)
{
  return TRConfRunMain([TRConfEngineYoga new], argc, argv);
}
