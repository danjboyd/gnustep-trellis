/* trellis-lint - checks Trellis layouts without running them.

     trellis-lint frames.json...                 layout rules on render output
     trellis-lint Screen.trellis [--owner X.h]   syntax, styles, and bindings:
                                                 every id must be an outlet and
                                                 every action a method of the
                                                 owner class declared in X.h

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <Foundation/Foundation.h>
#import "TRLint.h"
#import "TRMarkup.h"

static int gErrors = 0, gWarnings = 0;

static void TRReport(NSString *where, NSString *sev, NSString *rule, NSString *msg)
{
  if ([sev isEqualToString: @"error"]) gErrors++; else gWarnings++;
  printf("%s: %s [%s] %s\n", [where UTF8String], [sev UTF8String], [rule UTF8String], [msg UTF8String]);
}

/* Outlets (properties and IBOutlet ivars) and action selectors declared
   in an Objective-C header, for the @interface named `cls` (or the first
   @interface if cls is nil). A light scan, not a compiler. */
static BOOL TRScanHeader(NSString *path, NSString *cls, NSMutableSet *outlets, NSMutableSet *actions,
                         NSString **foundClass)
{
  NSString *src = [NSString stringWithContentsOfFile: path encoding: NSUTF8StringEncoding error: NULL];
  if (src == nil) return NO;
  NSRegularExpression *iface = [NSRegularExpression regularExpressionWithPattern:
    @"@interface\\s+(\\w+)[^\\n]*\\n([\\s\\S]*?)@end" options: 0 error: NULL];
  NSRegularExpression *prop = [NSRegularExpression regularExpressionWithPattern:
    @"@property\\s*(?:\\([^)]*\\))?([^;]*);" options: 0 error: NULL];
  NSRegularExpression *lastWord = [NSRegularExpression regularExpressionWithPattern:
    @"(\\w+)\\s*$" options: 0 error: NULL];
  NSRegularExpression *ivar = [NSRegularExpression regularExpressionWithPattern:
    @"IBOutlet\\s+\\w+\\s*\\*?\\s*(\\w+)\\s*;" options: 0 error: NULL];
  NSRegularExpression *meth = [NSRegularExpression regularExpressionWithPattern:
    @"^\\s*-\\s*\\(\\s*(?:IBAction|void)\\s*\\)\\s*(\\w+)\\s*:" options: NSRegularExpressionAnchorsMatchLines error: NULL];
  BOOL found = NO;
  for (NSTextCheckingResult *m in [iface matchesInString: src options: 0 range: NSMakeRange(0, [src length])])
    {
      NSString *name = [src substringWithRange: [m rangeAtIndex: 1]];
      if (cls && ![name isEqualToString: cls]) continue;
      NSString *body = [src substringWithRange: [m rangeAtIndex: 2]];
      NSRange all = NSMakeRange(0, [body length]);
      for (NSTextCheckingResult *p in [prop matchesInString: body options: 0 range: all])
        {
          /* "NSTextField *a, *b" declares a and b. */
          NSString *decl = [body substringWithRange: [p rangeAtIndex: 1]];
          for (NSString *piece in [decl componentsSeparatedByString: @","])
            {
              NSTextCheckingResult *w = [lastWord firstMatchInString: piece options: 0
                                                               range: NSMakeRange(0, [piece length])];
              if (w) [outlets addObject: [piece substringWithRange: [w rangeAtIndex: 1]]];
            }
        }
      for (NSTextCheckingResult *p in [ivar matchesInString: body options: 0 range: all])
        {
          /* KVC binds id="title" to an ivar _title too. */
          NSString *nm = [body substringWithRange: [p rangeAtIndex: 1]];
          [outlets addObject: nm];
          if ([nm hasPrefix: @"_"] && [nm length] > 1) [outlets addObject: [nm substringFromIndex: 1]];
        }
      for (NSTextCheckingResult *p in [meth matchesInString: body options: 0 range: all])
        [actions addObject: [[body substringWithRange: [p rangeAtIndex: 1]] stringByAppendingString: @":"]];
      *foundClass = name;
      found = YES;
      if (cls == nil) break;
    }
  return found;
}

/* ---- Colour pairing (Dark appearance / dark themes) ---- */

/* The element's colour declarations, later rules winning. */
static NSDictionary *TRColourDecls(TRMarkupDocument *doc, TRMarkupElement *e)
{
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  for (TRMatchedDeclarations *m in [doc declarationsForElement: e])
    {
      if (m.condition != nil) continue;   /* container-query overlays: not checked */
      for (NSString *decl in [m.declarations componentsSeparatedByString: @";"])
        {
          NSRange colon = [decl rangeOfString: @":"];
          if (colon.location == NSNotFound) continue;
          NSString *k = [[[decl substringToIndex: colon.location] stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
          NSString *v = [[[decl substringFromIndex: NSMaxRange(colon)] stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
          if ([k isEqualToString: @"background"]) k = @"background-color";
          if ([k isEqualToString: @"background-color"] || [k isEqualToString: @"color"]) d[k] = v;
        }
    }
  return d;
}

/* A colour that doesn't follow the appearance: not a system colour,
   transparent or currentColor. */
static BOOL TRIsFixedColour(NSString *v)
{
  if ([v length] == 0) return NO;
  static NSSet *dynamic;
  if (dynamic == nil)
    dynamic = [NSSet setWithObjects: @"transparent", @"currentcolor", @"inherit",
      @"canvas", @"canvastext", @"field", @"fieldtext", @"buttonface", @"buttontext", @"buttonborder",
      @"graytext", @"highlight", @"highlighttext", @"selecteditem", @"selecteditemtext",
      @"accentcolor", @"accentcolortext", @"linktext", @"mark", @"marktext",
      @"-tr-window-background", @"-tr-separator", @"-tr-secondary-text", @"-tr-error",
      @"-tr-warning-background", @"-tr-warning-text", nil];
  return ![dynamic containsObject: v];
}

/* Elements whose text draws straight onto their parent's background
   (buttons, pop-ups and fields have their own themed backgrounds). */
static BOOL TRDrawsTextOnParent(TRMarkupElement *e)
{
  NSString *n = e.name;
  return [n isEqualToString: @"label"] || [n isEqualToString: @"text"]
      || [n isEqualToString: @"checkbox"] || [n isEqualToString: @"radio"];
}

static void TRLintColours(TRMarkupDocument *doc, NSString *path)
{
  for (TRMarkupElement *e in [doc allElements])
    {
      NSDictionary *d = TRColourDecls(doc, e);
      NSString *where = [NSString stringWithFormat: @"%@:%lu:%lu", path, (unsigned long)e.line, (unsigned long)e.column];
      NSString *bg = d[@"background-color"], *fg = d[@"color"];
      if (TRDrawsTextOnParent(e) && TRIsFixedColour(fg))
        {
          /* Fixed text colour: the nearest background must be fixed too. */
          NSString *under = nil;
          for (TRMarkupElement *p = e.parent; p != nil && under == nil; p = p.parent)
            under = TRColourDecls(doc, p)[@"background-color"];
          if (!TRIsFixedColour(bg) && !TRIsFixedColour(under))
            TRReport(where, @"warning", @"colour-pair", [NSString stringWithFormat:
              @"color %@ is fixed, but the background behind it follows the appearance; in a dark appearance it may vanish. Use a system colour (CanvasText, GrayText) or set a background", fg]);
        }
      if (TRIsFixedColour(bg) && ![e.name isEqualToString: @"button"] && ![e.name isEqualToString: @"popup"]
          && ![e.name isEqualToString: @"field"])
        {
          /* Fixed background: text drawn on it must not follow the appearance. */
          NSUInteger loose = 0;
          NSMutableArray *stack = [NSMutableArray arrayWithObject: e];
          while ([stack count])
            {
              TRMarkupElement *x = [stack lastObject];
              [stack removeLastObject];
              NSDictionary *xd = (x == e) ? d : TRColourDecls(doc, x);
              if (x != e && xd[@"background-color"] != nil) continue;   /* covered by its own background */
              if (TRDrawsTextOnParent(x) && xd[@"color"] == nil) loose++;
              [stack addObjectsFromArray: x.children];
            }
          if (loose > 0)
            TRReport(where, @"warning", @"colour-pair", [NSString stringWithFormat:
              @"background %@ is fixed, but %lu text element(s) on it use the system text colour; in a dark appearance they vanish. Use system colours (Canvas, CanvasText) or set color on them",
              bg, (unsigned long)loose]);
        }
    }
}

/* hidden on the element or an ancestor (the loader's reading: bare,
   "hidden" or yes hide; no/false/off/0 don't). */
static BOOL TRLintHidden(TRMarkupElement *e)
{
  for (; e != nil; e = e.parent)
    {
      NSString *h = e.attributes[@"hidden"];
      if (h == nil) continue;
      NSString *l = [h lowercaseString];
      if (![l isEqualToString: @"no"] && ![l isEqualToString: @"false"]
          && ![l isEqualToString: @"off"] && ![l isEqualToString: @"0"])
        return YES;
    }
  return NO;
}

/* Accessibility: every control needs a name assistive apps can read. */
static void TRLintAccessibility(TRMarkupDocument *doc, NSString *path)
{
  NSMutableSet *labelled = [NSMutableSet set];
  NSMutableDictionary *byId = [NSMutableDictionary dictionary];
  for (TRMarkupElement *e in [doc allElements])
    {
      if ([e identifier]) byId[[e identifier]] = e;
      if (e.attributes[@"label-for"]) [labelled addObject: e.attributes[@"label-for"]];
    }
  NSSet *ids = [NSSet setWithArray: [byId allKeys]];
  NSSet *needsLabel = [NSSet setWithObjects: @"field", @"popup", @"slider", @"progress", @"image", @"view",
                                             @"segmented", nil];
  NSSet *titled = [NSSet setWithObjects: @"button", @"checkbox", @"radio", nil];
  for (TRMarkupElement *e in [doc allElements])
    {
      NSString *where = [NSString stringWithFormat: @"%@:%lu:%lu", path, (unsigned long)e.line, (unsigned long)e.column];
      NSDictionary *a = e.attributes;
      NSString *target = a[@"label-for"];
      if (target && ![ids containsObject: target])
        TRReport(where, @"error", @"label-for", [NSString stringWithFormat: @"label-for=\"%@\": no element with that id", target]);
      else if (target && TRLintHidden(byId[target]) && !TRLintHidden(e))
        TRReport(where, @"warning", @"label-for", [NSString stringWithFormat:
          @"label-for=\"%@\": that element is hidden but this label isn't; hide them together (wrap both in one box and hide it)", target]);
      /* A segment without a title has no name to read or click. */
      if ([e.name isEqualToString: @"segmented"])
        {
          NSUInteger blank = 0;
          for (TRMarkupElement *c in e.children)
            if ([c.name isEqualToString: @"item"]
                && [[(c.attributes[@"title"] ?: c.text ?: @"") stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0)
              blank++;
          if (a[@"items"])
            for (NSString *t in [a[@"items"] componentsSeparatedByString: @","])
              if ([[t stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]] length] == 0) blank++;
          if (blank)
            TRReport(where, @"warning", @"unlabeled", [NSString stringWithFormat:
              @"<segmented> has %lu item(s) with no title: every segment needs text", (unsigned long)blank]);
        }
      /* tabindex: an integer; a positive one in a template is shared by
         every copy, so all the copies jump ahead of the rest of the
         screen (and of each other's order). */
      NSString *ti = a[@"tabindex"];
      if (ti)
        {
          NSScanner *sc = [NSScanner scannerWithString: ti];
          NSInteger tv = 0;
          if (![sc scanInteger: &tv] || ![sc isAtEnd])
            TRReport(where, @"error", @"tabindex", [NSString stringWithFormat: @"tabindex=\"%@\": use a whole number", ti]);
          else if (tv > 0)
            for (TRMarkupElement *p = e.parent; p; p = p.parent)
              if ([p.name isEqualToString: @"template"])
                {
                  TRReport(where, @"warning", @"tabindex", [NSString stringWithFormat:
                    @"tabindex=\"%ld\" in a <template>: every copy shares it, so the copies jump ahead of the rest of the screen; leave Tab in document order (drop it, or use -1)", (long)tv]);
                  break;
                }
        }
      /* disabled: yes/no, on a control or a container of controls. */
      NSString *dis = a[@"disabled"];
      if (dis)
        {
          NSString *l = dis;   /* case as the loader reads it */
          BOOL known = [l length] == 0 || [l isEqualToString: @"disabled"]
            || [@[ @"yes", @"true", @"on", @"1", @"no", @"false", @"off", @"0" ] containsObject: l];
          if (!known)
            TRReport(where, @"error", @"disabled", [NSString stringWithFormat: @"disabled=\"%@\": use yes or no", dis]);
          else if ([@[ @"label", @"text", @"image", @"spacer", @"separator", @"progress" ] containsObject: e.name])
            TRReport(where, @"warning", @"disabled", [NSString stringWithFormat:
              @"<%@ disabled> has no effect: only controls (and containers of them) can be disabled", e.name]);
        }
      NSString *role = a[@"role"];
      if (role && ![role isEqualToString: @"group"] && ![role isEqualToString: @"none"])
        TRReport(where, @"error", @"role", [NSString stringWithFormat: @"role \"%@\" is not supported (use group or none)", role]);
      if ([role isEqualToString: @"none"] || [a[@"a11y-label"] length]) continue;
      if ([e identifier] && [labelled containsObject: [e identifier]]) continue;
      NSString *n = e.name;
      if ([needsLabel containsObject: n])
        {
          if ([n isEqualToString: @"field"] && [a[@"placeholder"] length]) continue;
          NSString *ident = [e identifier];
          TRReport(where, @"warning", @"unlabeled", ident
            ? [NSString stringWithFormat: @"<%@ id=\"%@\"> has no accessible name: add a <label label-for=\"%@\">, a11y-label=\"...\", or role=\"none\" if it's decorative", n, ident, ident]
            : [NSString stringWithFormat: @"<%@> has no accessible name: add a11y-label=\"...\" (or an id and a <label label-for>), or role=\"none\" if it's decorative", n]);
        }
      else if ([titled containsObject: n])
        {
          NSString *t = [e.text stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
          if ([t length] == 0)
            TRReport(where, @"warning", @"unlabeled", [NSString stringWithFormat:
              @"<%@> has no title: give it text or a11y-label=\"...\"", n]);
        }
    }
}

/* The element's unconditional declarations, later ones winning. */
static NSDictionary *TRAllDecls(TRMarkupDocument *doc, TRMarkupElement *e)
{
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  for (TRMatchedDeclarations *m in [doc declarationsForElement: e])
    {
      if (m.condition != nil) continue;
      for (NSString *decl in [m.declarations componentsSeparatedByString: @";"])
        {
          NSRange colon = [decl rangeOfString: @":"];
          if (colon.location == NSNotFound) continue;
          NSString *k = [[[decl substringToIndex: colon.location] stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
          d[k] = [[decl substringFromIndex: NSMaxRange(colon)] stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
  return d;
}

/* Children of display: block don't grow or shrink (since 0.6), so flex,
   flex-grow, flex-shrink and flex-basis on them do nothing. */
static void TRLintBlockChildren(TRMarkupDocument *doc, NSString *path)
{
  for (TRMarkupElement *e in [doc allElements])
    {
      if (e.parent == nil || ![TRAllDecls(doc, e.parent)[@"display"] isEqualToString: @"block"]) continue;
      NSDictionary *d = TRAllDecls(doc, e);
      for (NSString *k in @[@"flex", @"flex-grow", @"flex-shrink", @"flex-basis"])
        if (d[k])
          {
            NSString *where = [NSString stringWithFormat: @"%@:%lu:%lu", path, (unsigned long)e.line, (unsigned long)e.column];
            TRReport(where, @"warning", @"block-flex", [NSString stringWithFormat:
              @"<%@> %@ has no effect: its parent is display: block, whose children don't grow or shrink", e.name, k]);
            break;
          }
    }
}

static void TRLintTrellis(NSString *path, NSString *header)
{
  NSError *err = nil;
  TRMarkupDocument *doc = [TRMarkupDocument documentWithContentsOfFile: path error: &err];
  if (doc == nil)
    {
      TRReport(path, @"error", @"syntax", [err localizedDescription]);
      return;
    }
  /* Ids are unique per scope: the main tree, and each template (a
     template's copies are separate trees). */
  NSMutableDictionary *scopes = [NSMutableDictionary dictionary];
  for (TRMarkupElement *e in [doc allElements])
    {
      NSString *ident = [e identifier];
      NSString *where = [NSString stringWithFormat: @"%@:%lu:%lu", path, (unsigned long)e.line, (unsigned long)e.column];
      TRMarkupElement *scope = nil;
      for (TRMarkupElement *p = e.parent; p; p = p.parent)
        if ([p.name isEqualToString: @"template"]) { scope = p; break; }
      if (scope == nil)
        for (NSString *k in doc.templates)
          for (TRMarkupElement *p = e; p; p = p.parent)
            if (p == doc.templates[k]) scope = p;
      NSValue *key = [NSValue valueWithNonretainedObject: scope];
      NSMutableSet *ids = scopes[key];
      if (ids == nil) scopes[key] = ids = [NSMutableSet set];
      if (ident && [ids containsObject: ident])
        TRReport(where, @"error", @"duplicate-id", [NSString stringWithFormat: @"id '%@' is used twice", ident]);
      if (ident) [ids addObject: ident];
      /* Unitless lengths are accepted but are not CSS. */
      for (TRMatchedDeclarations *m in [doc declarationsForElement: e])
        {
          NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
            @"(?:^|;)\\s*(width|height|min-width|min-height|max-width|max-height|gap|padding|margin|flex-basis|top|left|right|bottom)\\s*:\\s*([1-9][0-9.]*)\\s*(?:;|$)"
                                                                               options: 0 error: NULL];
          NSTextCheckingResult *r = [re firstMatchInString: m.declarations options: 0
                                                     range: NSMakeRange(0, [m.declarations length])];
          if (r)
            TRReport(where, @"warning", @"unitless", [NSString stringWithFormat: @"%@: %@ has no unit (write %@px)",
                       [m.declarations substringWithRange: [r rangeAtIndex: 1]],
                       [m.declarations substringWithRange: [r rangeAtIndex: 2]],
                       [m.declarations substringWithRange: [r rangeAtIndex: 2]]]);
        }
    }
  /* <virtual>: templates only, and template= names one of them. */
  for (TRMarkupElement *e in [doc allElements])
    {
      if (![e.name isEqualToString: @"virtual"]) continue;
      NSString *where = [NSString stringWithFormat: @"%@:%lu:%lu", path, (unsigned long)e.line, (unsigned long)e.column];
      NSMutableSet *ids = [NSMutableSet set];
      for (TRMarkupElement *c in e.children)
        {
          if (![c.name isEqualToString: @"template"] || c.attributes[@"id"] == nil || [c.children count] != 1)
            TRReport(where, @"error", @"virtual", [NSString stringWithFormat:
              @"<virtual> may only contain <template id=\"...\"> elements with one child each, not <%@>", c.name]);
          else
            [ids addObject: c.attributes[@"id"]];
        }
      if ([ids count] == 0)
        TRReport(where, @"error", @"virtual", @"<virtual> has no <template>");
      NSString *t = e.attributes[@"template"];
      if (t && ![ids containsObject: t])
        TRReport(where, @"error", @"virtual", [NSString stringWithFormat: @"template=\"%@\" is not one of its <template>s", t]);
      NSString *layout = e.attributes[@"layout"];
      if (layout && ![layout isEqualToString: @"list"] && ![layout isEqualToString: @"grid"])
        TRReport(where, @"error", @"virtual", [NSString stringWithFormat: @"layout=\"%@\": use list or grid", layout]);
    }
  /* <split>: direction and divider values, at least one pane. */
  for (TRMarkupElement *e in [doc allElements])
    {
      if (![e.name isEqualToString: @"split"]) continue;
      NSString *where = [NSString stringWithFormat: @"%@:%lu:%lu", path, (unsigned long)e.line, (unsigned long)e.column];
      NSString *dir = e.attributes[@"direction"];
      if (dir && ![dir isEqualToString: @"row"] && ![dir isEqualToString: @"column"])
        TRReport(where, @"error", @"split", [NSString stringWithFormat: @"direction=\"%@\": use row or column", dir]);
      NSString *div = e.attributes[@"divider"];
      if (div && ![div isEqualToString: @"thin"] && ![div isEqualToString: @"thick"] && ![div isEqualToString: @"pane"])
        TRReport(where, @"error", @"split", [NSString stringWithFormat: @"divider=\"%@\": use thin, thick or pane", div]);
      if ([e.children count] == 0)
        TRReport(where, @"error", @"split", @"<split> has no panes");
    }
  /* <segmented>: items, tracking, selection. */
  for (TRMarkupElement *e in [doc allElements])
    {
      if (![e.name isEqualToString: @"segmented"]) continue;
      NSString *where = [NSString stringWithFormat: @"%@:%lu:%lu", path, (unsigned long)e.line, (unsigned long)e.column];
      NSMutableArray *titles = [NSMutableArray array];
      NSUInteger chosen = 0;
      for (TRMarkupElement *c in e.children)
        {
          if (![c.name isEqualToString: @"item"])
            {
              TRReport(where, @"error", @"segmented", [NSString stringWithFormat:
                @"<segmented> may only contain <item> elements, not <%@>", c.name]);
              continue;
            }
          NSString *sel = c.attributes[@"selected"];
          if ([sel isEqualToString: @"yes"] || [sel isEqualToString: @"true"]) chosen++;
          [titles addObject: c.attributes[@"title"] ?: [c text] ?: @""];
        }
      for (NSString *t in [e.attributes[@"items"] componentsSeparatedByString: @","])
        [titles addObject: [t stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]]];
      if ([titles count] == 0)
        TRReport(where, @"error", @"segmented", @"<segmented> has no items (use <item> children or items=\"A, B\")");
      NSString *tracking = e.attributes[@"tracking"] ?: @"one";
      if (![tracking isEqualToString: @"one"] && ![tracking isEqualToString: @"any"] && ![tracking isEqualToString: @"momentary"])
        TRReport(where, @"error", @"segmented", [NSString stringWithFormat: @"tracking=\"%@\": use one, any or momentary", tracking]);
      NSString *sel = e.attributes[@"selected"];
      if (sel && ![titles containsObject: sel])
        TRReport(where, @"error", @"segmented", [NSString stringWithFormat: @"selected=\"%@\": no item has that title", sel]);
      if (sel) chosen++;
      if ([tracking isEqualToString: @"momentary"] && chosen > 0)
        TRReport(where, @"error", @"segmented", @"<segmented tracking=\"momentary\"> has no selection; drop selected");
      if ([tracking isEqualToString: @"one"] && chosen > 1)
        TRReport(where, @"error", @"segmented", @"<segmented tracking=\"one\"> can select only one item");
    }
  TRLintColours(doc, path);
  TRLintAccessibility(doc, path);
  TRLintBlockChildren(doc, path);
  if (header == nil) return;
  NSMutableSet *outlets = [NSMutableSet set], *actions = [NSMutableSet set];
  NSString *cls = nil;
  if (!TRScanHeader(header, doc.ownerClassName, outlets, actions, &cls))
    {
      TRReport(header, @"error", @"owner", doc.ownerClassName
        ? [NSString stringWithFormat: @"no @interface %@ in this header", doc.ownerClassName]
        : @"no @interface in this header");
      return;
    }
  for (TRMarkupElement *e in [doc allElements])
    {
      BOOL inTemplate = NO;
      for (TRMarkupElement *p = e; p; p = p.parent)
        if ([p.name isEqualToString: @"template"]) inTemplate = YES;
      for (TRMarkupElement *t in [doc.templates allValues])
        for (TRMarkupElement *p = e; p; p = p.parent) if (p == t) inTemplate = YES;
      NSString *where = [NSString stringWithFormat: @"%@:%lu:%lu", path, (unsigned long)e.line, (unsigned long)e.column];
      NSString *ident = [e identifier];
      NSString *noOutlet = e.attributes[@"no-outlet"];
      if (ident && !inTemplate && ![noOutlet isEqualToString: @"yes"] && ![outlets containsObject: ident])
        TRReport(where, @"error", @"outlet", [NSString stringWithFormat:
          @"id '%@' has no matching outlet in %@ (%@)", ident, cls, header]);
      NSString *action = e.attributes[@"action"];
      if (action && ![actions containsObject: action])
        TRReport(where, @"error", @"action", [NSString stringWithFormat:
          @"action '%@' is not declared by %@ (%@)", action, cls, header]);
    }
}

int main(int argc, const char **argv)
{
  @autoreleasepool
    {
      NSString *owner = nil;
      NSMutableArray *inputs = [NSMutableArray array];
      for (int i = 1; i < argc; i++)
        {
          NSString *a = [NSString stringWithUTF8String: argv[i]];
          if ([a isEqualToString: @"--owner"] && i + 1 < argc)
            owner = [NSString stringWithUTF8String: argv[++i]];
          else
            [inputs addObject: a];
        }
      if ([inputs count] == 0)
        {
          fprintf(stderr, "usage: trellis-lint frames.json... | Screen.trellis [--owner Owner.h]\n");
          return 2;
        }
      for (NSString *path in inputs)
        {
          if ([[path pathExtension] isEqualToString: @"trellis"])
            {
              TRLintTrellis(path, owner);
              continue;
            }
          NSData *data = [NSData dataWithContentsOfFile: path];
          NSDictionary *doc = data ? [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL] : nil;
          if (![doc isKindOfClass: [NSDictionary class]] || doc[@"root"] == nil)
            {
              TRReport(path, @"error", @"input", @"not a Trellis frame dump or .trellis file");
              continue;
            }
          NSDictionary *vp = doc[@"viewport"];
          for (NSDictionary *f in TRLintFrameTree(doc[@"root"], [vp[@"width"] doubleValue], [vp[@"height"] doubleValue]))
            TRReport(path, f[@"severity"], f[@"rule"], f[@"message"]);
        }
      printf("%d error(s), %d warning(s)\n", gErrors, gWarnings);
      return gErrors ? 1 : 0;
    }
}
