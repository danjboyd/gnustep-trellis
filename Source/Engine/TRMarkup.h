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
   no cascade between files, no inheritance (except `direction`).

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
   @container blocks come back with their condition. */
- (NSArray<TRMatchedDeclarations *> *)declarationsForElement:(TRMarkupElement *)element;

/* Every element, depth first. */
- (NSArray<TRMarkupElement *> *)allElements;

@end
