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
     label                non-editable NSTextField (text content = string)
     text                 wrapping, non-editable NSTextField
     field                editable NSTextField (placeholder=, secure="yes")
     button               NSButton (title= or text content, action=, default="yes")
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

/* Fills views from sample content: {"id": "text" | {"string"|"title"|
   "items"|"state"|"value"|"hidden": ...}}. Unknown ids are errors. */
+ (BOOL)applySample:(NSDictionary *)sample toView:(NSView *)root error:(NSError **)error;

/* Finds a view by its identifier in a tree. */
+ (NSView *)viewWithIdentifier:(NSString *)identifier inView:(NSView *)root;

@end

/* An NSScrollView whose document view is a Trellis column. */
@interface TRScrollBox : NSScrollView
@property (nonatomic, readonly) TRBoxView *contentBox;
@end
