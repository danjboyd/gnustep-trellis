/* TRMarkup.h - parser for .trellis layout files (Foundation only).

   A .trellis file is HTML-like element markup with one root element, plus
   an optional <style> block of CSS scoped to the file:

     <column id="ask" class="card">
       <label id="title" class="title">Hello</label>
       <button title="OK" action="ok:"/>
     </column>
     <style>
       .card { padding: 16px; gap: 8px; }
       column > label { color: #333; }
       @container (min-width: 560px) { .card { flex-direction: row; } }
     </style>

   Selectors: type, .class, #id, compounds (button.primary), descendant
   (A B) and child (A > B) combinators, comma lists. No pseudo-classes,
   no cascade between files, no inheritance (except `direction` and
   custom properties).

   Custom properties: `--name: value` declares one; it inherits down the
   element tree, and `var(--name)` or `var(--name, fallback)` uses it in
   any value. Built-in tokens (`--tr-font-size`, `--tr-space-m`,
   `--tr-radius`, `--tr-accent`, ...) are defined everywhere; the AppKit
   layer sets the metric ones from the running theme. A custom property
   set inside an @container block applies only within that block. A
   top-level <template>'s copies see the document root's properties.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <Foundation/Foundation.h>

extern NSString *const TRMarkupErrorDomain;

@interface TRMarkupElement : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *attributes;
@property (nonatomic, readonly) NSArray<NSString *> *attributeOrder;
@property (nonatomic, readonly) NSArray<TRMarkupElement *> *children;
@property (nonatomic, readonly, weak) TRMarkupElement *parent;
/* Text content directly inside the element, whitespace-collapsed. */
@property (nonatomic, readonly) NSString *text;
/* The element's text pieces (NSString, not collapsed) and child elements
   (TRMarkupElement) in document order: rich text like
   `Hello <b>there</b>`. */
@property (nonatomic, readonly) NSArray *content;
@property (nonatomic, readonly) NSUInteger line, column;
@property (nonatomic, readonly) NSArray<NSString *> *classes;
- (NSString *)identifier;
@end

/* One matched set of declarations, with the condition it applies under
   (nil = always). */
@interface TRMatchedDeclarations : NSObject
@property (nonatomic, readonly) NSString *declarations;
@property (nonatomic, readonly) NSString *condition;
@property (nonatomic, readonly) NSUInteger line;
@end

@interface TRMarkupDocument : NSObject

+ (instancetype)documentWithContentsOfFile:(NSString *)path error:(NSError **)error;
+ (instancetype)documentWithString:(NSString *)source name:(NSString *)name
                             error:(NSError **)error;

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) TRMarkupElement *root;
/* <template id="..."> elements, by id. */
@property (nonatomic, readonly) NSDictionary<NSString *, TRMarkupElement *> *templates;
/* The owner class named by <!-- owner: Class --> or <trellis owner="...">, if any. */
@property (nonatomic, readonly) NSString *ownerClassName;

/* The declarations that apply to an element, in cascade order (lowest
   first): built-in element defaults, matching rules by specificity then
   source order, then the inline style="" attribute. Rules inside
   @container blocks come back with their condition. Custom properties
   are resolved: declarations come back without --name entries and with
   var() replaced. */
- (NSArray<TRMatchedDeclarations *> *)declarationsForElement:(TRMarkupElement *)element;

/* Custom properties in effect at an element (built-ins included). */
- (NSDictionary<NSString *, NSString *> *)customPropertiesForElement:(TRMarkupElement *)element;
/* The built-in tokens, for every document. Set by libTrellis from the
   theme (names starting --tr-); defaults are typical desktop values. */
+ (void)setBuiltinCustomProperties:(NSDictionary<NSString *, NSString *> *)properties;
+ (NSDictionary<NSString *, NSString *> *)builtinCustomProperties;
+ (NSDictionary<NSString *, NSString *> *)defaultBuiltinCustomProperties;

/* Every element, depth first. */
- (NSArray<TRMarkupElement *> *)allElements;

@end
