/* TRStyle.h - the CSS properties of one Trellis box.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#ifndef TRELLIS_TRSTYLE_H
#define TRELLIS_TRSTYLE_H

#import "TRTypes.h"

@class TRNode;

/* Raw storage, read by the layout algorithm. */
typedef struct {
  TRDisplay display;
  TRPosition position;
  TRDirection direction;
  TRFlexDirection flexDirection;
  TRFlexWrap flexWrap;
  TRAlign justifyContent;
  TRAlign alignItems;
  TRAlign alignSelf;
  TRAlign alignContent;
  TROverflow overflow;
  TRBoxSizing boxSizing;
  TRFloat flexGrow;
  TRFloat flexShrink;
  TRValue flexBasis;
  TRValue width, height;
  TRValue minWidth, minHeight;
  TRValue maxWidth, maxHeight;
  TRFloat aspectRatio;          /* width / height; NAN = auto */
  TRValue margin[4];            /* indexed by TREdge */
  TRValue padding[4];
  TRValue border[4];            /* border widths; auto is treated as 0 */
  TRValue inset[4];             /* left/top/right/bottom */
  TRValue rowGap, columnGap;
  NSInteger order;
  /* Grid */
  TRAlign justifyItems;         /* normal = stretch */
  TRAlign justifySelf;          /* auto = justify-items */
  BOOL gridAutoFlowColumn;      /* grid-auto-flow: column */
  BOOL gridAutoFlowDense;       /* grid-auto-flow: ... dense */
  /* "safe" overflow alignment (CSS Box Alignment 4.4): when the content
     overflows, align as start. */
  BOOL justifyContentSafe, alignContentSafe;
} TRStyleStorage;
/* TRStyleStorage is internal (docs/api.md): its layout changes between
   versions. Use TRStyle's properties. */

extern TRStyleStorage TRStyleStorageInitial(void);

/* A TRStyle holds the layout properties of one box using exact CSS names
   and initial values. Three ways to set them, all equivalent:

     style.flexDirection = TRFlexDirectionColumn;          // typed
     [style setValue:@"column" forProperty:@"flex-direction"];  // name/value
     [style applyDeclarations:@"flex-direction: column; gap: 8px" error:NULL];

   Declarations that are not layout properties (background-color, color,
   font-size, border-radius, ...) are kept in -otherDeclarations for the
   view layer. There are no selectors and no cascade. */
@interface TRStyle : NSObject <NSCopying>
{
@public
  TRStyleStorage _s;
  /* Grid properties are kept as validated CSS text; TRGrid.m parses them. */
  NSString *_gridTemplateColumns, *_gridTemplateRows;
  NSString *_gridAutoColumns, *_gridAutoRows;
  NSArray<NSArray<NSString *> *> *_gridTemplateAreas;   /* rows of cell names; "." = empty */
  NSString *_gridRowStart, *_gridRowEnd, *_gridColumnStart, *_gridColumnEnd;
}

+ (instancetype)style;
/* Parse a declaration block: "display:flex; gap: 8px; padding: 4px 8px".
   Returns nil and fills *error on a syntax error or unknown value. */
+ (instancetype)styleWithDeclarations:(NSString *)declarations;
+ (instancetype)styleWithDeclarations:(NSString *)declarations error:(NSError **)error;
/* Keys: camelCase or kebab-case CSS names. Values: NSNumber (px) or
   NSString (any CSS value: "50%", "auto", "1 1 0", "4px 8px"). */
+ (instancetype)styleWithDictionary:(NSDictionary *)dict error:(NSError **)error;

- (BOOL)applyDeclarations:(NSString *)declarations error:(NSError **)error;
- (BOOL)applyDictionary:(NSDictionary *)dict error:(NSError **)error;
- (BOOL)setValue:(id)value forProperty:(NSString *)property error:(NSError **)error;

/* Non-layout declarations, keyed by kebab-case name, values as written. */
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *otherDeclarations;

/* The box this style belongs to; changes mark it dirty. */
@property (nonatomic, weak) TRNode *owner;

/* Typed accessors. */
@property (nonatomic) TRDisplay display;
@property (nonatomic) TRPosition position;
@property (nonatomic) TRDirection direction;
@property (nonatomic) TRFlexDirection flexDirection;
@property (nonatomic) TRFlexWrap flexWrap;
@property (nonatomic) TRAlign justifyContent;
@property (nonatomic) TRAlign alignItems;
@property (nonatomic) TRAlign alignSelf;
@property (nonatomic) TRAlign alignContent;
@property (nonatomic) TROverflow overflow;
@property (nonatomic) TRBoxSizing boxSizing;
@property (nonatomic) TRFloat flexGrow;
@property (nonatomic) TRFloat flexShrink;
@property (nonatomic) TRValue flexBasis;
@property (nonatomic) TRValue width;
@property (nonatomic) TRValue height;
@property (nonatomic) TRValue minWidth;
@property (nonatomic) TRValue minHeight;
@property (nonatomic) TRValue maxWidth;
@property (nonatomic) TRValue maxHeight;
@property (nonatomic) TRFloat aspectRatio;
@property (nonatomic) TRValue rowGap;
@property (nonatomic) TRValue columnGap;
@property (nonatomic) NSInteger order;
- (TRValue)marginForEdge:(TREdge)edge;
- (void)setMargin:(TRValue)v forEdge:(TREdge)edge;
- (TRValue)paddingForEdge:(TREdge)edge;
- (void)setPadding:(TRValue)v forEdge:(TREdge)edge;
- (TRValue)borderWidthForEdge:(TREdge)edge;
- (void)setBorderWidth:(TRValue)v forEdge:(TREdge)edge;
- (TRValue)insetForEdge:(TREdge)edge;
- (void)setInset:(TRValue)v forEdge:(TREdge)edge;
/* Convenience: set all four edges. */
- (void)setMargin:(TRValue)v;
- (void)setPadding:(TRValue)v;
- (void)setGap:(TRValue)v;

/* The style as CSS declarations, non-initial values only. */
- (NSString *)declarationString;

@end

extern NSString *const TRStyleErrorDomain;

#endif
