/* TRLoader.m - builds views from .trellis layout files.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRLoader.h"
#import <objc/runtime.h>

static NSError *TRLoadError(TRMarkupDocument *doc, TRMarkupElement *e, NSString *fmt, ...) NS_FORMAT_FUNCTION(3,4);
static NSError *TRLoadError(TRMarkupDocument *doc, TRMarkupElement *e, NSString *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  NSString *m = [[NSString alloc] initWithFormat: fmt arguments: ap];
  va_end(ap);
  NSString *full = [NSString stringWithFormat: @"%@:%lu:%lu: %@", doc.name,
                     (unsigned long)e.line, (unsigned long)e.column, m];
  return [NSError errorWithDomain: TRMarkupErrorDomain code: 10
                         userInfo: @{NSLocalizedDescriptionKey: full}];
}

static BOOL TRYes(NSString *v)
{
  return v && ([v isEqualToString: @"yes"] || [v isEqualToString: @"true"] || [v isEqualToString: @"on"]
               || [v isEqualToString: @"1"]);
}

/* ------------------------------------------------------------------ */

@implementation TRScrollBox
{
  TRBoxView *_box;
}

- (instancetype)initWithFrame:(NSRect)frame
{
  if ((self = [super initWithFrame: frame]) != nil)
    {
      _box = [TRBoxView boxWithStyle: @"flex-direction: column"];
      [self setHasVerticalScroller: YES];
      [self setHasHorizontalScroller: NO];
      [self setBorderType: NSNoBorder];
      [self setDrawsBackground: NO];
      [self setDocumentView: _box];
    }
  return self;
}

- (TRBoxView *)contentBox
{
  return _box;
}

- (void)layoutContent
{
  NSSize cs = [self contentSize];
  [_box.node layoutWithAvailableSize: TRSizeMake(cs.width, NAN)];
  CGFloat h = MAX(ceil(_box.node.layoutFrame.height), cs.height);
  [_box setFrame: NSMakeRect(0, 0, cs.width, h)];
  [_box layoutTrellis];
}

/* GNUstep's -setFrame: does not go through -setFrameSize:, so both. */
- (void)setFrameSize:(NSSize)size
{
  [super setFrameSize: size];
  [self layoutContent];
}

- (void)setFrame:(NSRect)frame
{
  [super setFrame: frame];
  [self layoutContent];
}

@end

/* ------------------------------------------------------------------ */

@interface TRPlaceholderView : TRBoxView
@end
@implementation TRPlaceholderView
@end

@implementation TRLoader

static NSTextField *TRMakeLabel(NSString *text, BOOL wraps)
{
  NSTextField *f = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
  [f setStringValue: text ?: @""];
  [f setEditable: NO];
  [f setSelectable: NO];
  [f setBezeled: NO];
  [f setBordered: NO];
  [f setDrawsBackground: NO];
  /* Explicit either way: GNUstep text-field cells wrap by default, Apple's
     do not. Labels are single-line unless asked; lint flags clipping. */
  [[f cell] setWraps: wraps];
  [[f cell] setLineBreakMode: wraps ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail];
  return f;
}

/* Builds the view for one element (and its subtree). */
+ (NSView *)viewForElement:(TRMarkupElement *)e document:(TRMarkupDocument *)doc
                     owner:(id)owner error:(NSError **)error
{
  NSString *n = e.name;
  NSDictionary *a = e.attributes;
  NSString *text = [e text];
  NSView *v = nil;
  BOOL container = NO;

  if ([n isEqualToString: @"column"] || [n isEqualToString: @"row"] || [n isEqualToString: @"box"])
    {
      v = [[TRBoxView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
      container = YES;
    }
  else if ([n isEqualToString: @"scroll"])
    v = [[TRScrollBox alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
  else if ([n isEqualToString: @"label"])
    v = TRMakeLabel(a[@"text"] ?: text, TRYes(a[@"wraps"]));
  else if ([n isEqualToString: @"text"])
    v = TRMakeLabel(a[@"text"] ?: text, YES);
  else if ([n isEqualToString: @"field"])
    {
      NSTextField *f = TRYes(a[@"secure"]) ? [[NSSecureTextField alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)]
                                          : [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
      [f setStringValue: a[@"value"] ?: text ?: @""];
      [[f cell] setWraps: NO];
      [[f cell] setScrollable: YES];
      if (a[@"placeholder"]) [[f cell] setPlaceholderString: a[@"placeholder"]];
      if (a[@"editable"] && !TRYes(a[@"editable"])) [f setEditable: NO];
      v = f;
    }
  else if ([n isEqualToString: @"button"] || [n isEqualToString: @"checkbox"] || [n isEqualToString: @"radio"])
    {
      NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
      if ([n isEqualToString: @"checkbox"]) [b setButtonType: NSSwitchButton];
      else if ([n isEqualToString: @"radio"]) [b setButtonType: NSRadioButton];
      else [b setBezelStyle: NSRoundedBezelStyle];
      [b setTitle: a[@"title"] ?: text ?: @""];
      if (a[@"state"]) [b setState: TRYes(a[@"state"]) ? NSOnState : NSOffState];
      if (TRYes(a[@"default"])) [b setKeyEquivalent: @"\r"];
      v = b;
    }
  else if ([n isEqualToString: @"popup"])
    {
      NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 10, 10) pullsDown: NO];
      for (TRMarkupElement *c in e.children)
        {
          if (![c.name isEqualToString: @"item"])
            {
              if (error) *error = TRLoadError(doc, c, @"<popup> may only contain <item> elements, not <%@>", c.name);
              return nil;
            }
          [p addItemWithTitle: c.attributes[@"title"] ?: [c text]];
        }
      if (a[@"items"])
        for (NSString *t in [a[@"items"] componentsSeparatedByString: @","])
          [p addItemWithTitle: [t stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]]];
      if (a[@"selected"]) [p selectItemWithTitle: a[@"selected"]];
      v = p;
    }
  else if ([n isEqualToString: @"image"])
    {
      NSImageView *iv = [[NSImageView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
      NSImage *img = nil;
      if (a[@"src"])
        {
          NSString *path = a[@"src"];
          if (![path isAbsolutePath])
            path = [[doc.name stringByDeletingLastPathComponent] stringByAppendingPathComponent: path];
          img = [[NSImage alloc] initWithContentsOfFile: path];
        }
      else if (a[@"name"])
        img = [NSImage imageNamed: a[@"name"]];
      [iv setImage: img];
      [iv setImageScaling: NSImageScaleProportionallyUpOrDown];
      v = iv;
    }
  else if ([n isEqualToString: @"slider"])
    {
      NSSlider *s = [[NSSlider alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)];
      if (a[@"min"]) [s setMinValue: [a[@"min"] doubleValue]];
      if (a[@"max"]) [s setMaxValue: [a[@"max"] doubleValue]];
      if (a[@"value"]) [s setDoubleValue: [a[@"value"] doubleValue]];
      v = s;
    }
  else if ([n isEqualToString: @"progress"])
    {
      NSProgressIndicator *p = [[NSProgressIndicator alloc] initWithFrame: NSMakeRect(0, 0, 100, 16)];
      [p setIndeterminate: TRYes(a[@"indeterminate"])];
      if (a[@"max"]) [p setMaxValue: [a[@"max"] doubleValue]];
      if (a[@"value"]) [p setDoubleValue: [a[@"value"] doubleValue]];
      v = p;
    }
  else if ([n isEqualToString: @"separator"])
    {
      NSBox *b = [[NSBox alloc] initWithFrame: NSMakeRect(0, 0, 100, 1)];
      [b setBoxType: NSBoxSeparator];
      [b setTitlePosition: NSNoTitle];
      v = b;
    }
  else if ([n isEqualToString: @"spacer"])
    v = [[NSView alloc] initWithFrame: NSZeroRect];
  else if ([n isEqualToString: @"view"])
    {
      NSString *type = a[@"type"];
      Class cls = type ? NSClassFromString(type) : Nil;
      if (cls && [cls isSubclassOfClass: [NSView class]])
        v = [[cls alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
      else
        {
          TRPlaceholderView *ph = [TRPlaceholderView boxWithStyle:
            @"min-height: 40px; min-width: 80px; align-items: center; justify-content: center; "
            @"background-color: #efe6f7; border: 1px solid #a68bc4"];
          [ph addSubview: TRMakeLabel(type ?: @"view", NO) style: @"color: #6a4c93"];
          v = ph;
        }
    }
  else
    {
      if (error) *error = TRLoadError(doc, e, @"unknown element <%@>", n);
      return nil;
    }

  if (!container && ![n isEqualToString: @"popup"] && ![n isEqualToString: @"scroll"] && [e.children count])
    {
      if (error) *error = TRLoadError(doc, e.children[0], @"<%@> cannot contain elements", n);
      return nil;
    }

  NSString *ident = [e identifier];
  if (ident) [v setIdentifier: ident];

  /* Action. */
  NSString *action = a[@"action"];
  if (action)
    {
      if (![v isKindOfClass: [NSControl class]])
        {
          if (error) *error = TRLoadError(doc, e, @"<%@> does not send actions", n);
          return nil;
        }
      SEL sel = NSSelectorFromString(action);
      if (owner != nil && ![owner respondsToSelector: sel])
        {
          if (error) *error = TRLoadError(doc, e, @"action '%@': %@ does not implement -%@",
                                          action, NSStringFromClass([owner class]), action);
          return nil;
        }
      [(NSControl *)v setTarget: owner];
      [(NSControl *)v setAction: sel];
    }

  /* Outlet. */
  if (ident && owner != nil)
    {
      NSString *setter = [NSString stringWithFormat: @"set%@%@:", [[ident substringToIndex: 1] uppercaseString],
                                                     [ident substringFromIndex: 1]];
      BOOL hasIvar = class_getInstanceVariable([owner class], [ident UTF8String]) != NULL
        || class_getInstanceVariable([owner class], [[@"_" stringByAppendingString: ident] UTF8String]) != NULL;
      if ([owner respondsToSelector: NSSelectorFromString(setter)] || hasIvar)
        [owner setValue: v forKey: ident];
      else if (!TRYes(a[@"no-outlet"]))
        {
          if (error) *error = TRLoadError(doc, e, @"id '%@': %@ has no outlet named '%@' (add a property, or no-outlet=\"yes\")",
                                          ident, NSStringFromClass([owner class]), ident);
          return nil;
        }
    }

  /* Children. */
  TRBoxView *box = container ? (TRBoxView *)v
                 : ([v isKindOfClass: [TRScrollBox class]] ? [(TRScrollBox *)v contentBox] : nil);
  if (box)
    for (TRMarkupElement *c in e.children)
      {
        NSView *cv = [self viewForElement: c document: doc owner: owner error: error];
        if (cv == nil) return nil;
        [box addSubview: cv];
        if (![self applyStylesOf: c toView: cv inBox: box document: doc error: error]) return nil;
      }
  return v;
}

+ (BOOL)applyStylesOf:(TRMarkupElement *)e toView:(NSView *)v inBox:(TRBoxView *)box
             document:(TRMarkupDocument *)doc error:(NSError **)error
{
  NSMutableArray *base = [NSMutableArray array];
  NSArray *matched = [doc declarationsForElement: e];
  for (TRMatchedDeclarations *m in matched)
    if (m.condition == nil) [base addObject: m.declarations];
  @try
    {
      NSString *joined = [base componentsJoinedByString: @"; "];
      if (box == nil)
        [(TRBoxView *)v setStyleDeclarations: joined];
      else
        [box setStyleDeclarations: joined forSubview: v];
      for (TRMatchedDeclarations *m in matched)
        {
          if (m.condition == nil) continue;
          if (box == nil) [(TRBoxView *)v addConditionalStyle: m.declarations when: m.condition];
          else [box addConditionalStyle: m.declarations when: m.condition forSubview: v];
        }
    }
  @catch (NSException *ex)
    {
      if (error) *error = TRLoadError(doc, e, @"%@", [ex reason]);
      return NO;
    }
  return YES;
}

+ (TRBoxView *)loadFile:(NSString *)path owner:(id)owner error:(NSError **)error
{
  TRMarkupDocument *doc = [TRMarkupDocument documentWithContentsOfFile: path error: error];
  if (doc == nil) return nil;
  return [self loadDocument: doc owner: owner error: error];
}

+ (TRBoxView *)loadDocument:(TRMarkupDocument *)doc owner:(id)owner error:(NSError **)error
{
  TRMarkupElement *root = doc.root;
  if (![@[@"column", @"row", @"box"] containsObject: root.name])
    {
      if (error) *error = TRLoadError(doc, root, @"the root element must be <column>, <row> or <box>, not <%@>", root.name);
      return nil;
    }
  NSView *v = [self viewForElement: root document: doc owner: owner error: error];
  if (v == nil) return nil;
  if (![self applyStylesOf: root toView: v inBox: nil document: doc error: error]) return nil;
  return (TRBoxView *)v;
}

+ (NSView *)instantiateTemplate:(NSString *)templateId ofDocument:(TRMarkupDocument *)doc
                          owner:(id)owner error:(NSError **)error
{
  TRMarkupElement *t = doc.templates[templateId];
  if (t == nil || [t.children count] != 1)
    {
      if (error) *error = [NSError errorWithDomain: TRMarkupErrorDomain code: 11 userInfo: @{
        NSLocalizedDescriptionKey: [NSString stringWithFormat: @"%@: no <template id=\"%@\"> with exactly one child",
                                     doc.name, templateId]}];
      return nil;
    }
  TRMarkupElement *e = t.children[0];
  /* Template instances are not outlets of the owner. */
  NSView *v = [self viewForElement: e document: doc owner: nil error: error];
  if (v == nil) return nil;
  if ([v isKindOfClass: [TRBoxView class]]
      && ![self applyStylesOf: e toView: v inBox: nil document: doc error: error])
    return nil;
  (void)owner;
  return v;
}

+ (NSView *)viewWithIdentifier:(NSString *)identifier inView:(NSView *)root
{
  if ([[root identifier] isEqualToString: identifier]) return root;
  NSArray *subs = [root isKindOfClass: [NSScrollView class]]
    ? @[[(NSScrollView *)root documentView]] : [root subviews];
  for (NSView *s in subs)
    {
      NSView *f = [self viewWithIdentifier: identifier inView: s];
      if (f) return f;
    }
  return nil;
}

+ (BOOL)applySample:(NSDictionary *)sample toView:(NSView *)root error:(NSError **)error
{
  for (NSString *ident in sample)
    {
      if ([ident hasPrefix: @"_"]) continue;   /* comments / metadata */
      NSView *v = [self viewWithIdentifier: ident inView: root];
      if (v == nil)
        {
          if (error) *error = [NSError errorWithDomain: TRMarkupErrorDomain code: 12 userInfo: @{
            NSLocalizedDescriptionKey: [NSString stringWithFormat: @"sample: no view with id '%@'", ident]}];
          return NO;
        }
      id val = sample[ident];
      NSDictionary *d = [val isKindOfClass: [NSDictionary class]] ? val : nil;
      NSString *str = [val isKindOfClass: [NSString class]] ? val : d[@"string"];
      if ([v isKindOfClass: [NSPopUpButton class]])
        {
          NSArray *items = [val isKindOfClass: [NSArray class]] ? val : d[@"items"];
          if (items) { [(NSPopUpButton *)v removeAllItems]; [(NSPopUpButton *)v addItemsWithTitles: items]; }
          if (d[@"selected"]) [(NSPopUpButton *)v selectItemWithTitle: d[@"selected"]];
        }
      else if ([v isKindOfClass: [NSButton class]])
        {
          NSString *title = d[@"title"] ?: str;
          if (title) [(NSButton *)v setTitle: title];
          if (d[@"state"]) [(NSButton *)v setState: [d[@"state"] boolValue] ? NSOnState : NSOffState];
        }
      else if ([v isKindOfClass: [NSControl class]])
        {
          if (str) [(NSControl *)v setStringValue: str];
          if (d[@"value"]) [(NSControl *)v setDoubleValue: [d[@"value"] doubleValue]];
        }
      else if ([v isKindOfClass: [NSProgressIndicator class]] && d[@"value"])
        [(NSProgressIndicator *)v setDoubleValue: [d[@"value"] doubleValue]];
      if (d[@"hidden"]) [v setHidden: [d[@"hidden"] boolValue]];
    }
  return YES;
}

@end
