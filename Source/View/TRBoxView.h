/* TRBoxView.h - an NSView container laid out by Trellis.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#ifndef TRELLIS_TRBOXVIEW_H
#define TRELLIS_TRBOXVIEW_H

#import <AppKit/AppKit.h>
#import "TrellisEngine.h"

/* A TRBoxView is a flex container whose children are real NSViews.

   - Subviews are laid out by their Trellis styles. Leaves (NSControls and
     other views) are measured by their cell size or intrinsicContentSize,
     so themes keep drawing them exactly as before: Trellis only sets
     frames.
   - Nested TRBoxViews join their parent's box tree, so a whole screen is
     laid out in one pass.
   - The outermost TRBoxView lays out whenever its size changes. To its own
     superview it is an ordinary view: it can sit inside autoresizing-mask
     or Auto Layout parents, and reports its laid-out size as
     intrinsicContentSize.
   - Non-layout declarations are applied as drawing: background-color,
     border-color, border-radius on boxes; color, font-size, font-weight,
     text-align on text controls. */
@interface TRBoxView : NSView

+ (instancetype)boxWithStyle:(NSString *)declarations;
- (instancetype)initWithStyle:(NSString *)declarations;

/* This box's node in the layout tree. */
@property (nonatomic, readonly) TRNode *node;
/* Shorthand for node.style. */
@property (nonatomic, copy) TRStyle *style;
- (void)setStyleDeclarations:(NSString *)declarations;

/* Adds a subview with its style (inline CSS declarations; nil = default).
   Plain -addSubview: works too and gives the view a default style. */
- (void)addSubview:(NSView *)view style:(NSString *)declarations;
- (TRNode *)nodeForSubview:(NSView *)view;
- (void)setStyleDeclarations:(NSString *)declarations forSubview:(NSView *)view;

/* Container queries (see TRNode). */
- (void)addConditionalStyle:(NSString *)declarations when:(NSString *)condition;
- (void)addConditionalStyle:(NSString *)declarations when:(NSString *)condition
                 forSubview:(NSView *)view;

/* Call after changing a subview's content (text, image) outside Trellis;
   it is remeasured on the next layout. Text and title changes of
   NSControls are noticed automatically. */
- (void)invalidateSubview:(NSView *)view;

/* Lays out now (only meaningful on the outermost box). */
- (void)layoutTrellis;
/* The outermost TRBoxView of this tree. */
- (TRBoxView *)rootBox;

@end

/* CSS colour strings: #rgb, #rrggbb, #rrggbbaa, rgb(), rgba(), and a few
   names (black, white, gray/grey, red, green, blue, transparent). */
NSColor *TRColorFromCSS(NSString *css);

#endif
