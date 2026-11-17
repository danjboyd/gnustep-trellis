/* TRLoader.h - builds views from .trellis layout files.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRMarkup.h"

/* Elements and what they build:

     column, row, box     TRBoxView (column/row set flex-direction)
     scroll               NSScrollView whose document view is a column box
     virtual              TRVirtualBox: a scroller that builds views only for
                          the items on screen (layout="list|grid", template=,
                          estimated-size=, overscan=; <template id> children)
     label                non-editable NSTextField (text content = string)
     text                 wrapping, non-editable NSTextField
     field                editable NSTextField (placeholder=, secure="yes")
     button               NSButton (title= or text content, action=, default="yes",
                          bordered="no" for a flat, title-only button)
     checkbox, radio      NSButton switch/radio (title=, state="on")
     popup                NSPopUpButton (<item>Title</item> children or items="A,B")
     image                NSImageView (src= file relative to the .trellis file, or name=)
     slider               NSSlider (min=, max=, value=)
     progress             NSProgressIndicator (value=, max=, indeterminate="yes")
     separator            a 1px NSBox line
     spacer               an empty view with flex: 1
     view type="Class"    an instance of a custom NSView subclass; if the
                          class is not linked in, a labelled placeholder

   Bindings, when an owner is given:
     id="name"            the view is set on the owner by KVC (outlet "name")
     action="doIt:"       target = owner, action = doIt:
   A missing outlet or action is a load error (trellis-lint checks the same
   at build time). */
@interface TRLoader : NSObject

+ (TRBoxView *)loadFile:(NSString *)path owner:(id)owner error:(NSError **)error;
+ (TRBoxView *)loadDocument:(TRMarkupDocument *)document owner:(id)owner error:(NSError **)error;

/* Builds a fresh copy of a <template id="..."> element (for list rows). */
+ (NSView *)instantiateTemplate:(NSString *)templateId
                     ofDocument:(TRMarkupDocument *)document
                          owner:(id)owner
                          error:(NSError **)error;
/* The same for a <template> element (top-level or inside <virtual>). */
+ (NSView *)instantiateTemplateElement:(TRMarkupElement *)element
                            ofDocument:(TRMarkupDocument *)document
                                 error:(NSError **)error;

/* Fills views from sample content: {"id": "text" | {"string"|"title"|
   "items"|"state"|"value"|"hidden": ...}}. Unknown ids are errors. */
+ (BOOL)applySample:(NSDictionary *)sample toView:(NSView *)root error:(NSError **)error;

/* Finds a view by its identifier in a tree. */
+ (NSView *)viewWithIdentifier:(NSString *)identifier inView:(NSView *)root;

/* Dev hot-reload, off by default. While it's on, a box made by
   +loadFile:owner:error: is rebuilt whenever its file changes on disk:
   - the new tree takes the old one's place (window content view, or the
     same superview with the same frame and autoresizing mask);
   - outlets and actions are bound to the owner again, and the owner gets
     -trellisDidReload: if it implements it (refill content there);
   - TRLoaderDidReloadNotification is posted (object: the new box);
   - a file that no longer loads is reported on stderr and the old tree
     stays.
   Turn it on with TRELLIS_HOT_RELOAD=1 in the environment, the
   TRHotReload user default, or +setHotReloadEnabled:. Building libTrellis
   with hot_reload=no (make) or -DTR_NO_HOT_RELOAD compiles it out. */
+ (void)setHotReloadEnabled:(BOOL)enabled;
+ (BOOL)hotReloadEnabled;
/* Checks the watched files now; a timer does this every half second while
   hot reload is on. Returns the number of boxes rebuilt. */
+ (NSUInteger)reloadChangedFiles;

@end

@interface NSObject (TRHotReloadOwner)
/* Sent to the owner after hot reload rebuilt its box. */
- (void)trellisDidReload:(TRBoxView *)newRoot;
@end

extern NSString *const TRLoaderDidReloadNotification;

/* Sets the built-in CSS tokens' metrics (--tr-font-size, --tr-control-
   height, --tr-scroller-width, ...) from the running theme. Loading a
   document does this; call it before resolving styles yourself. */
void TRUpdateThemeTokens(void);

/* The cell of <button bordered="no">: a title-only button that draws
   its (attributed) title itself, in the colour its style sets. */
@interface TRFlatButtonCell : NSButtonCell
@end

/* An NSScrollView whose document view is a Trellis column. */
@interface TRScrollBox : NSScrollView
@property (nonatomic, readonly) TRBoxView *contentBox;
@end
