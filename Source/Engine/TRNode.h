/* TRNode.h - a box in a Trellis layout tree.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#ifndef TRELLIS_TRNODE_H
#define TRELLIS_TRNODE_H

#import "TRTypes.h"
#import "TRStyle.h"

/* Measures a leaf's content box. `available` is a constraint on the
   content box (padding and border already removed), to be read according
   to the mode (see TRMeasureMode). Return the content size. */
typedef TRSize (^TRMeasureBlock)(TRSize available,
                                 TRMeasureMode widthMode,
                                 TRMeasureMode heightMode);

/* The first baseline of a leaf at its final size, measured from the top
   of its border box. */
typedef TRFloat (^TRBaselineBlock)(TRSize size);

/* A box. Every box with children is a flex container (Trellis v1 has no
   block layout); a box without children is a leaf, sized by its style or
   by its measure block.

   A TRNode tree is pure geometry: it knows nothing about views, so the
   engine runs identically on GNUstep, on macOS and in tests. */
@interface TRNode : NSObject

+ (instancetype)node;
/* A node whose style is parsed from a dictionary (see TRStyle) or a
   CSS declaration string. Raises NSInvalidArgumentException on a bad
   style: styles are code, and a typo should fail loudly. */
+ (instancetype)nodeWithStyle:(id)styleDictionaryOrString;
+ (instancetype)nodeWithStyle:(id)styleDictionaryOrString
                     children:(NSArray<TRNode *> *)children;

/* The node's style. Mutating it marks the node dirty. Setting it copies. */
@property (nonatomic, copy) TRStyle *style;

/* Hidden: laid out as if `display: none`, whatever the style says, so
   showing it again restores the style's own display. Marks it dirty. */
@property (nonatomic, getter=isHidden) BOOL hidden;

/* Optional name, used in frame dumps and lint messages. */
@property (nonatomic, copy) NSString *identifier;

/* Any object the client wants to attach (the view layer stores its view). */
@property (nonatomic, weak) id context;

@property (nonatomic, readonly) NSArray<TRNode *> *children;
@property (nonatomic, readonly, weak) TRNode *parent;
- (void)addChild:(TRNode *)child;
- (void)insertChild:(TRNode *)child atIndex:(NSUInteger)index;
- (void)removeChild:(TRNode *)child;
- (void)removeAllChildren;

@property (nonatomic, copy) TRMeasureBlock measureBlock;
@property (nonatomic, copy) TRBaselineBlock baselineBlock;

/* Invalidates cached measurements of this node and its ancestors. Call it
   when a leaf's content (and so its measure result) changes. */
- (void)markDirty;
@property (nonatomic, readonly, getter=isDirty) BOOL dirty;

/* Lays out the tree rooted here. A defined available width or height
   lays the root out at exactly that size, unless the root's own style
   sets its size; NAN leaves that dimension to the content. */
- (void)layoutWithAvailableSize:(TRSize)available;
- (void)layoutWithAvailableSize:(TRSize)available direction:(TRDirection)direction;

/* Pixel-grid rounding applied after layout: frames are snapped to
   1/pixelScale. Default 1 (whole points). 0 disables rounding. */
@property (nonatomic) TRFloat pixelScale;

/* Results, valid after layout. */
@property (nonatomic, readonly) TRRect layoutFrame;      /* border box, relative to the parent's border box */
@property (nonatomic, readonly) TRDirection layoutDirection;
@property (nonatomic, readonly) TRSize contentSize;      /* extent of children, for scrolling */
- (TRFloat)layoutPaddingForEdge:(TREdge)edge;
- (TRFloat)layoutBorderForEdge:(TREdge)edge;
- (TRFloat)layoutMarginForEdge:(TREdge)edge;
/* Frame relative to the root of the tree. */
- (TRRect)absoluteFrame;
/* The first baseline, from the top of the border box. */
- (TRFloat)layoutBaseline;
/* YES if the node's content (measured size) does not fit its frame. */
@property (nonatomic, readonly) BOOL hasOverflow;

/* The laid-out tree as JSON-ready dictionaries:
   {id, x, y, width, height, style, children:[...]} */
- (NSDictionary *)frameDump;

@end

@interface TRNode (ContainerQueries)

/* Container queries. `condition` is evaluated against the inner width of
   the nearest ancestor whose style has `container-type: inline-size` (or
   the root, if there is none), after each layout pass; when it matches,
   `declarations` are applied on top of the node's style. Accepted forms:
   "(min-width: 560px)", "(max-width: 400px)", "width >= 560px",
   "width < 400px", joined with "and". Set the node's base style before
   adding conditions. */
- (BOOL)addConditionalStyle:(NSString *)declarations
                       when:(NSString *)condition
                      error:(NSError **)error;
/* The conditions that matched in the last layout. */
@property (nonatomic, readonly) NSArray<NSString *> *matchedConditions;

/* Internal (docs/api.md): where a container-query lookup continues when it
   reaches this root without finding a container. The view layer sets it
   on a scroller's content tree to the scroller's own node, so queries in
   scrolled content test the container outside the scroller. */
@property (nonatomic, weak) TRNode *containerQueryParent;

@end

#endif
