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

/* Keyboard focus order. The outermost TRBoxView links its focusable
   descendants into a nextKeyView loop after every layout: views with a
   positive tab index first (ascending), then the rest in document order;
   hidden views and tab index -1 are left out. CSS `order` doesn't change
   it, as in browsers. On GNUstep the chain is open and wraps through a
   private sentinel view (last -> sentinel -> first) that leads back in
   only while some member can become key, so a loop whose views are all
   hidden or disabled ends the search instead of spinning (GNUstep's
   -nextValidKeyView doesn't stop on its own). On Cocoa it is a
   closed ring (last -> first): AppKit's search stops by itself, and its
   key-view bookkeeping relies on the plain getters. Set
   managesKeyViewLoop = NO to build your own (Trellis then unlinks the
   views it linked). */
@property (nonatomic) BOOL managesKeyViewLoop;          /* default YES */
- (void)recalculateTrellisKeyViewLoop;
/* The first view in the loop (for -[NSWindow setInitialFirstResponder:]). */
@property (nonatomic, readonly) NSView *firstKeyView;
@end

/* The tab index of a view (markup: tabindex="N"); 0 when unset. */
void TRSetTabIndex(NSView *view, NSInteger index);
NSInteger TRTabIndex(NSView *view);

/* Accessibility (markup: a11y-label, label-for, role). Trellis records
   these on every platform; on Cocoa they are also set through
   NSAccessibility. GNUstep's AppKit has no accessibility setters yet, so
   there they are only readable through these functions. */
void TRSetAccessibilityLabel(NSView *view, NSString *label);
/* The explicit label, else the text of the view's title view, else nil. */
NSString *TRAccessibilityLabel(NSView *view);
/* The label that names a control (markup: <label label-for="id">). */
void TRSetAccessibilityTitleView(NSView *view, NSView *titleView);
NSView *TRAccessibilityTitleView(NSView *view);
/* "group" (a named container) or "none" (hidden from assistive apps). */
void TRSetAccessibilityRole(NSView *view, NSString *role);
NSString *TRAccessibilityRole(NSView *view);

/* CSS colour strings: #rgb, #rrggbb, #rrggbbaa, rgb(), rgba(), a few
   names, and CSS system colours (Canvas, CanvasText, ...; dynamic). */
NSColor *TRColorFromCSS(NSString *css);

#endif
