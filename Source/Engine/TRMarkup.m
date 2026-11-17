/* TRMarkup.m - parser for .trellis layout files.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRMarkup.h"
#import "TRStyle.h"

NSString *const TRMarkupErrorDomain = @"TRMarkupErrorDomain";

/* ------------------------------------------------------------------ */
#pragma mark Elements

@interface TRMarkupElement ()
{
@public
  NSString *_name;
  NSMutableDictionary *_attributes;
  NSMutableArray *_attributeOrder;
  NSMutableArray *_children;
  __weak TRMarkupElement *_parent;
  NSMutableString *_text;
  NSMutableArray *_content;     /* NSString and TRMarkupElement, in order */
  NSUInteger _line, _column;
}
@end

@implementation TRMarkupElement
- (instancetype)init
{
  if ((self = [super init]) != nil)
    {
      _attributes = [NSMutableDictionary dictionary];
      _attributeOrder = [NSMutableArray array];
      _children = [NSMutableArray array];
      _text = [NSMutableString string];
      _content = [NSMutableArray array];
    }
  return self;
}
- (NSArray *)content { return _content; }
- (NSString *)name { return _name; }
- (NSDictionary *)attributes { return _attributes; }
- (NSArray *)attributeOrder { return _attributeOrder; }
- (NSArray *)children { return _children; }
- (TRMarkupElement *)parent { return _parent; }
- (NSUInteger)line { return _line; }
- (NSUInteger)column { return _column; }
- (NSString *)identifier { return _attributes[@"id"]; }
- (NSString *)text
{
  NSArray *words = [_text componentsSeparatedByCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSMutableArray *w = [NSMutableArray array];
  for (NSString *s in words) if ([s length]) [w addObject: s];
  return [w componentsJoinedByString: @" "];
}
- (NSArray *)classes
{
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *c in [_attributes[@"class"] componentsSeparatedByCharactersInSet:
                         [NSCharacterSet whitespaceCharacterSet]])
    if ([c length]) [out addObject: c];
  return out;
}
- (NSString *)description
{
  return [NSString stringWithFormat: @"<%@%@> (line %lu)", _name,
           _attributes[@"id"] ? [@" #" stringByAppendingString: _attributes[@"id"]] : @"",
           (unsigned long)_line];
}
@end

@interface TRMatchedDeclarations ()
{
@public
  NSString *_declarations, *_condition;
  NSUInteger _line;
}
@end
@implementation TRMatchedDeclarations
- (NSString *)declarations { return _declarations; }
- (NSString *)condition { return _condition; }
- (NSUInteger)line { return _line; }
@end

/* ------------------------------------------------------------------ */
#pragma mark Selectors and rules

/* A compound selector: type? #id? .class* */
@interface TRCompound : NSObject
{
@public
  NSString *type, *ident;
  NSArray *classes;
  BOOL child;          /* combinator to the LEFT of this compound is '>' */
}
@end
@implementation TRCompound
@end

@interface TRRule : NSObject
{
@public
  NSArray *compounds;   /* left to right */
  NSString *declarations;
  NSString *condition;  /* @container condition, or nil */
  NSUInteger specificity, order, line;
}
@end
@implementation TRRule
@end

static BOOL TRCompoundMatches(TRCompound *c, TRMarkupElement *e)
{
  if (c->type && ![c->type isEqualToString: @"*"] && ![c->type isEqualToString: e->_name]) return NO;
  if (c->ident && ![c->ident isEqualToString: e->_attributes[@"id"]]) return NO;
  if ([c->classes count])
    {
      NSArray *ec = [e classes];
      for (NSString *k in c->classes) if (![ec containsObject: k]) return NO;
    }
  return YES;
}

/* Right-to-left matching with backtracking over descendant combinators. */
static BOOL TRMatchFrom(NSArray *compounds, NSInteger idx, TRMarkupElement *e)
{
  TRCompound *c = compounds[idx];
  if (!TRCompoundMatches(c, e)) return NO;
  if (idx == 0) return YES;
  if (c->child)
    return e->_parent != nil && TRMatchFrom(compounds, idx - 1, e->_parent);
  for (TRMarkupElement *p = e->_parent; p != nil; p = p->_parent)
    if (TRMatchFrom(compounds, idx - 1, p)) return YES;
  return NO;
}

/* ------------------------------------------------------------------ */
#pragma mark Document

@interface TRMarkupDocument ()
{
  NSString *_name;
  NSString *_src;
  NSUInteger _pos, _len;
  NSUInteger _lcPos, _lcLine, _lcCol;   /* last lineCol: answer, to resume from */
  TRMarkupElement *_root;
  NSMutableDictionary *_templates;
  NSMutableArray *_rules;
  NSString *_owner;
  NSError *_error;
  NSMapTable *_customCache;        /* element -> resolved custom properties */
}
@end

/* ---- Custom properties (--name, var()) ---- */

static NSDictionary *gBuiltinCustom;

/* "a: b; c: d(e;f)" -> [[a, b], [c, d(e;f)]]: split on ';' outside
   parentheses, then at the first ':'. Pieces without ':' are kept with
   a nil value (TRStyle reports them). */
static NSArray<NSArray<NSString *> *> *TRSplitDeclarations(NSString *decls)
{
  NSMutableArray *out = [NSMutableArray array];
  NSUInteger n = [decls length], start = 0;
  int depth = 0;
  NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  for (NSUInteger i = 0; i <= n; i++)
    {
      unichar c = i < n ? [decls characterAtIndex: i] : ';';
      if (c == '(') depth++;
      else if (c == ')' && depth > 0) depth--;
      else if (c == ';' && depth == 0)
        {
          NSString *piece = [[decls substringWithRange: NSMakeRange(start, i - start)] stringByTrimmingCharactersInSet: ws];
          start = i + 1;
          if ([piece length] == 0) continue;
          NSRange colon = [piece rangeOfString: @":"];
          if (colon.location == NSNotFound) { [out addObject: @[piece]]; continue; }
          [out addObject: @[[[piece substringToIndex: colon.location] stringByTrimmingCharactersInSet: ws],
                            [[piece substringFromIndex: NSMaxRange(colon)] stringByTrimmingCharactersInSet: ws]]];
        }
    }
  return out;
}

static NSString *TRJoinDeclarations(NSArray<NSArray<NSString *> *> *pairs)
{
  NSMutableArray *parts = [NSMutableArray array];
  for (NSArray *p in pairs)
    [parts addObject: [p count] > 1 ? [NSString stringWithFormat: @"%@: %@", p[0], p[1]] : p[0]];
  return [parts componentsJoinedByString: @"; "];
}

/* Replaces var(--name) and var(--name, fallback) in a value. Returns nil
   and sets *missing when a variable is undefined and has no fallback. */
static NSString *TRSubstituteVars(NSString *value, NSDictionary *vars, int depth, NSString **missing)
{
  if ([value rangeOfString: @"var("].location == NSNotFound) return value;
  if (depth > 16) { if (missing) *missing = @"(a cycle)"; return nil; }
  NSMutableString *out = [NSMutableString string];
  NSUInteger n = [value length], i = 0;
  while (i < n)
    {
      NSRange r = [value rangeOfString: @"var(" options: 0 range: NSMakeRange(i, n - i)];
      if (r.location == NSNotFound) { [out appendString: [value substringFromIndex: i]]; break; }
      [out appendString: [value substringWithRange: NSMakeRange(i, r.location - i)]];
      /* the matching ')' and the first top-level ',' */
      NSUInteger j = NSMaxRange(r), comma = NSNotFound;
      int d = 1;
      for (; j < n; j++)
        {
          unichar c = [value characterAtIndex: j];
          if (c == '(') d++;
          else if (c == ')' && --d == 0) break;
          else if (c == ',' && d == 1 && comma == NSNotFound) comma = j;
        }
      if (j >= n) { if (missing) *missing = @"(an unclosed var())"; return nil; }
      NSUInteger nameEnd = comma != NSNotFound ? comma : j;
      NSString *name = [[value substringWithRange: NSMakeRange(NSMaxRange(r), nameEnd - NSMaxRange(r))]
        stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      NSString *rep = vars[name];
      if (rep == nil && comma != NSNotFound)
        rep = [[value substringWithRange: NSMakeRange(comma + 1, j - comma - 1)]
          stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (rep == nil) { if (missing) *missing = name; return nil; }
      rep = TRSubstituteVars(rep, vars, depth + 1, missing);
      if (rep == nil) return nil;
      [out appendString: rep];
      i = j + 1;
    }
  return out;
}

@implementation TRMarkupDocument

+ (instancetype)documentWithContentsOfFile:(NSString *)path error:(NSError **)error
{
  NSString *src = [NSString stringWithContentsOfFile: path encoding: NSUTF8StringEncoding error: error];
  if (src == nil) return nil;
  return [self documentWithString: src name: path error: error];
}

+ (instancetype)documentWithString:(NSString *)source name:(NSString *)name error:(NSError **)error
{
  TRMarkupDocument *d = [[self alloc] init];
  d->_name = [name copy] ?: @"<string>";
  d->_src = [source copy];
  d->_len = [source length];
  d->_templates = [NSMutableDictionary dictionary];
  d->_rules = [NSMutableArray array];
  if (![d parse])
    {
      if (error) *error = d->_error;
      return nil;
    }
  return d;
}

- (NSString *)name { return _name; }
- (TRMarkupElement *)root { return _root; }
- (NSDictionary *)templates { return _templates; }

+ (void)setBuiltinCustomProperties:(NSDictionary<NSString *, NSString *> *)properties
{
  gBuiltinCustom = [properties copy];
}

+ (NSDictionary<NSString *, NSString *> *)builtinCustomProperties
{
  if (gBuiltinCustom == nil) gBuiltinCustom = [self defaultBuiltinCustomProperties];
  return gBuiltinCustom;
}

/* Values for a typical desktop theme; the AppKit layer replaces the
   metrics with the running theme's (TRLoader). */
+ (NSDictionary<NSString *, NSString *> *)defaultBuiltinCustomProperties
{
  return @{
    @"--tr-font-size": @"13px", @"--tr-small-font-size": @"11px", @"--tr-label-font-size": @"10px",
    @"--tr-title-font-size": @"17px",
    @"--tr-control-height": @"22px", @"--tr-field-height": @"22px", @"--tr-scroller-width": @"15px",
    @"--tr-space-xs": @"2px", @"--tr-space-s": @"4px", @"--tr-space-m": @"8px", @"--tr-space-l": @"12px",
    @"--tr-space-xl": @"20px",
    @"--tr-radius-s": @"4px", @"--tr-radius": @"6px", @"--tr-radius-l": @"10px",
    @"--tr-text": @"CanvasText", @"--tr-surface": @"Canvas", @"--tr-window": @"-tr-window-background",
    @"--tr-muted": @"GrayText", @"--tr-border": @"-tr-separator", @"--tr-accent": @"AccentColor",
    @"--tr-accent-text": @"AccentColorText", @"--tr-link": @"LinkText", @"--tr-danger": @"-tr-error",
    @"--tr-warning": @"-tr-warning-background", @"--tr-warning-text": @"-tr-warning-text",
    @"--tr-highlight": @"Highlight", @"--tr-highlight-text": @"HighlightText",
  };
}

/* The custom properties an element sees: its parent's (a top-level
   template's root sees the document root's), then its own unconditional
   declarations in cascade order, each resolved where it is defined. */
- (NSDictionary<NSString *, NSString *> *)customPropertiesForElement:(TRMarkupElement *)e
{
  if (e == nil) return [TRMarkupDocument builtinCustomProperties];
  if (_customCache == nil) _customCache = [NSMapTable strongToStrongObjectsMapTable];
  NSDictionary *cached = [_customCache objectForKey: e];
  if (cached) return cached;
  TRMarkupElement *parent = e->_parent;
  BOOL topTemplate = NO;
  if (parent == nil && e != _root)
    for (NSString *k in _templates) if (_templates[k] == e) topTemplate = YES;
  NSMutableDictionary *vars = [(parent ? [self customPropertiesForElement: parent]
                                : (topTemplate && _root ? [self customPropertiesForElement: _root]
                                   : [TRMarkupDocument builtinCustomProperties])) mutableCopy];
  for (TRMatchedDeclarations *m in [self rawDeclarationsForElement: e])
    {
      if (m->_condition != nil) continue;
      for (NSArray *pair in TRSplitDeclarations(m->_declarations))
        if ([pair count] > 1 && [pair[0] hasPrefix: @"--"])
          {
            NSString *v = TRSubstituteVars(pair[1], vars, 0, NULL);
            if (v) vars[pair[0]] = v;
          }
    }
  [_customCache setObject: vars forKey: e];
  return vars;
}

/* Declarations with custom properties removed and var() replaced. nil
   (and *missing) if a variable is undefined. A conditional block's own
   custom properties apply inside it (they don't inherit). */
- (NSString *)resolveDeclarations:(NSString *)decls vars:(NSDictionary *)vars missing:(NSString **)missing
{
  if ([decls rangeOfString: @"--"].location == NSNotFound && [decls rangeOfString: @"var("].location == NSNotFound)
    return decls;
  NSMutableDictionary *local = nil;
  NSMutableArray *out = [NSMutableArray array];
  for (NSArray *pair in TRSplitDeclarations(decls))
    {
      if ([pair count] > 1 && [pair[0] hasPrefix: @"--"])
        {
          if (local == nil) local = [vars mutableCopy];
          NSString *v = TRSubstituteVars(pair[1], local, 0, NULL);
          if (v) local[pair[0]] = v;
          continue;
        }
      if ([pair count] > 1)
        {
          NSString *v = TRSubstituteVars(pair[1], local ?: vars, 0, missing);
          if (v == nil) return nil;
          [out addObject: @[pair[0], v]];
        }
      else
        [out addObject: pair];
    }
  return TRJoinDeclarations(out);
}
- (NSString *)ownerClassName { return _owner; }

/* ---- Errors with line:column ---- */

/* Positions come in increasing order while parsing, so each call resumes
   from the last one (scanning from the start every time made parsing
   quadratic in the file's size); an earlier position starts over. */
- (void)lineCol:(NSUInteger)pos line:(NSUInteger *)line col:(NSUInteger *)col
{
  NSUInteger i = 0, l = 1, c = 1;
  if (_lcLine > 0 && pos >= _lcPos) { i = _lcPos; l = _lcLine; c = _lcCol; }
  for (; i < pos && i < _len; i++)
    {
      if ([_src characterAtIndex: i] == '\n') { l++; c = 1; }
      else c++;
    }
  _lcPos = i; _lcLine = l; _lcCol = c;
  *line = l; *col = c;
}

- (BOOL)failAt:(NSUInteger)pos message:(NSString *)fmt, ... NS_FORMAT_FUNCTION(2,3)
{
  va_list ap;
  va_start(ap, fmt);
  NSString *m = [[NSString alloc] initWithFormat: fmt arguments: ap];
  va_end(ap);
  NSUInteger l, c;
  [self lineCol: pos line: &l col: &c];
  NSString *full = [NSString stringWithFormat: @"%@:%lu:%lu: %@", _name, (unsigned long)l, (unsigned long)c, m];
  _error = [NSError errorWithDomain: TRMarkupErrorDomain code: 1
                           userInfo: @{NSLocalizedDescriptionKey: full,
                                       @"line": @(l), @"column": @(c)}];
  return NO;
}

/* ---- Lexing helpers ---- */

- (unichar)peek { return _pos < _len ? [_src characterAtIndex: _pos] : 0; }
- (BOOL)lookingAt:(NSString *)s
{
  return _pos + [s length] <= _len
    && [[_src substringWithRange: NSMakeRange(_pos, [s length])] isEqualToString: s];
}
- (void)skipSpace
{
  while (_pos < _len && [[NSCharacterSet whitespaceAndNewlineCharacterSet]
                          characterIsMember: [_src characterAtIndex: _pos]])
    _pos++;
}
static BOOL TRIsNameChar(unichar c)
{
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
    || c == '-' || c == '_' || c == ':' || c == '.';
}
- (NSString *)readName
{
  NSUInteger start = _pos;
  while (_pos < _len && TRIsNameChar([_src characterAtIndex: _pos])) _pos++;
  return _pos > start ? [_src substringWithRange: NSMakeRange(start, _pos - start)] : nil;
}

static NSString *TRDecodeEntities(NSString *s)
{
  if ([s rangeOfString: @"&"].location == NSNotFound) return s;
  s = [s stringByReplacingOccurrencesOfString: @"&lt;" withString: @"<"];
  s = [s stringByReplacingOccurrencesOfString: @"&gt;" withString: @">"];
  s = [s stringByReplacingOccurrencesOfString: @"&quot;" withString: @"\""];
  s = [s stringByReplacingOccurrencesOfString: @"&apos;" withString: @"'"];
  s = [s stringByReplacingOccurrencesOfString: @"&nbsp;" withString: @" "];
  return [s stringByReplacingOccurrencesOfString: @"&amp;" withString: @"&"];
}

/* ---- Markup ---- */

- (BOOL)parse
{
  NSMutableArray *stack = [NSMutableArray array];
  while (_pos < _len)
    {
      if ([self lookingAt: @"<!--"])
        {
          NSRange end = [_src rangeOfString: @"-->" options: 0 range: NSMakeRange(_pos, _len - _pos)];
          if (end.location == NSNotFound) return [self failAt: _pos message: @"unterminated comment"];
          NSString *body = [_src substringWithRange: NSMakeRange(_pos + 4, end.location - _pos - 4)];
          NSRange o = [body rangeOfString: @"owner:"];
          if (o.location != NSNotFound && _owner == nil)
            _owner = [[body substringFromIndex: NSMaxRange(o)]
              stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
          _pos = NSMaxRange(end);
          continue;
        }
      if ([self lookingAt: @"</"])
        {
          NSUInteger at = _pos;
          _pos += 2;
          NSString *n = [self readName];
          [self skipSpace];
          if ([self peek] != '>') return [self failAt: _pos message: @"expected '>'"];
          _pos++;
          TRMarkupElement *top = [stack lastObject];
          if (top == nil) return [self failAt: at message: @"unexpected </%@>", n];
          if (![top->_name isEqualToString: n])
            return [self failAt: at message: @"</%@> does not match <%@> opened at line %lu",
                                 n, top->_name, (unsigned long)top->_line];
          [stack removeLastObject];
          continue;
        }
      if ([self peek] == '<')
        {
          NSUInteger at = _pos;
          _pos++;
          NSString *n = [self readName];
          if (n == nil) return [self failAt: _pos message: @"expected an element name after '<'"];
          TRMarkupElement *e = [TRMarkupElement new];
          e->_name = n;
          [self lineCol: at line: &e->_line col: &e->_column];
          for (;;)
            {
              [self skipSpace];
              unichar c = [self peek];
              if (c == '>' || c == '/') break;
              if (c == 0) return [self failAt: _pos message: @"unterminated <%@>", n];
              NSUInteger attrAt = _pos;
              NSString *an = [self readName];
              if (an == nil) return [self failAt: _pos message: @"bad attribute in <%@>", n];
              [self skipSpace];
              NSString *av = @"yes";
              if ([self peek] == '=')
                {
                  _pos++;
                  [self skipSpace];
                  unichar q = [self peek];
                  if (q != '"' && q != '\'')
                    return [self failAt: _pos message: @"attribute %@ needs a quoted value", an];
                  _pos++;
                  NSUInteger vs = _pos;
                  while (_pos < _len && [_src characterAtIndex: _pos] != q) _pos++;
                  if (_pos >= _len) return [self failAt: vs message: @"unterminated attribute value"];
                  av = TRDecodeEntities([_src substringWithRange: NSMakeRange(vs, _pos - vs)]);
                  _pos++;
                }
              if (e->_attributes[an] != nil)
                return [self failAt: attrAt message: @"duplicate attribute %@", an];
              e->_attributes[an] = av;
              [e->_attributeOrder addObject: an];
            }
          BOOL selfClosing = NO;
          if ([self peek] == '/') { selfClosing = YES; _pos++; }
          if ([self peek] != '>') return [self failAt: _pos message: @"expected '>' to close <%@>", n];
          _pos++;

          if ([n isEqualToString: @"style"])
            {
              if (selfClosing) continue;
              NSRange end = [_src rangeOfString: @"</style>" options: 0 range: NSMakeRange(_pos, _len - _pos)];
              if (end.location == NSNotFound) return [self failAt: at message: @"<style> is not closed"];
              NSUInteger cssStart = _pos;
              _pos = NSMaxRange(end);
              if (![self parseCSS: [_src substringWithRange: NSMakeRange(cssStart, end.location - cssStart)]
                           offset: cssStart condition: nil])
                return NO;
              continue;
            }
          if ([n isEqualToString: @"trellis"])
            {
              /* Optional document wrapper: <trellis owner="Class"> ... </trellis> */
              if (e->_attributes[@"owner"]) _owner = e->_attributes[@"owner"];
              if (!selfClosing) [stack addObject: e];
              e->_name = @"trellis";
              continue;
            }
          TRMarkupElement *parent = [stack lastObject];
          if (parent != nil && ![parent->_name isEqualToString: @"trellis"])
            {
              e->_parent = parent;
              [parent->_children addObject: e];
              [parent->_content addObject: e];
            }
          else if ([n isEqualToString: @"template"])
            {
              NSString *tid = e->_attributes[@"id"];
              if (tid == nil) return [self failAt: at message: @"<template> needs an id"];
              _templates[tid] = e;
            }
          else
            {
              if (_root != nil)
                return [self failAt: at message: @"a .trellis file has one root element; <%@> is a second one (root is <%@> at line %lu)",
                                     n, _root->_name, (unsigned long)_root->_line];
              _root = e;
            }
          if (!selfClosing) [stack addObject: e];
          continue;
        }
      /* Text */
      NSUInteger ts = _pos;
      while (_pos < _len && [_src characterAtIndex: _pos] != '<') _pos++;
      NSString *t = [_src substringWithRange: NSMakeRange(ts, _pos - ts)];
      TRMarkupElement *top = [stack lastObject];
      if (top != nil && ![top->_name isEqualToString: @"trellis"])
        {
          NSString *dt = TRDecodeEntities(t);
          [top->_text appendString: dt];
          [top->_content addObject: dt];
        }
      else if ([[t stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] length])
        return [self failAt: ts message: @"text outside the root element"];
    }
  if ([stack count] && !([stack count] == 1 && [((TRMarkupElement *)stack[0])->_name isEqualToString: @"trellis"]))
    {
      TRMarkupElement *open = [stack lastObject];
      NSUInteger l = open->_line;
      return [self failAt: _len message: @"<%@> opened at line %lu is never closed", open->_name, (unsigned long)l];
    }
  if (_root == nil) return [self failAt: 0 message: @"no root element"];
  return [self validateStyles];
}

/* Every inline style must parse, so errors point at the element. */
- (BOOL)validateStyles
{
  for (TRMarkupElement *e in [self allElements])
    {
      /* var(): every use must resolve, to a valid value. */
      for (TRMatchedDeclarations *m in [self rawDeclarationsForElement: e])
        {
          if ([m->_declarations rangeOfString: @"var("].location == NSNotFound) continue;
          NSString *missing = nil;
          NSString *r = [self resolveDeclarations: m->_declarations vars: [self customPropertiesForElement: e]
                                          missing: &missing];
          NSError *err = nil;
          NSString *msg = nil;
          if (r == nil)
            msg = [missing hasPrefix: @"("] ? [NSString stringWithFormat: @"var(): %@", [missing substringWithRange: NSMakeRange(1, [missing length] - 2)]]
                : [NSString stringWithFormat: @"var(%@) is not defined here (define it on this element or an ancestor, or give a fallback)", missing];
          else if ([TRStyle styleWithDeclarations: r error: &err] == nil)
            msg = [NSString stringWithFormat: @"after var(): %@", [err localizedDescription]];
          if (msg)
            {
              _error = [NSError errorWithDomain: TRMarkupErrorDomain code: 3 userInfo: @{
                NSLocalizedDescriptionKey: [NSString stringWithFormat: @"%@:%lu:%lu: <%@>: %@",
                  _name, (unsigned long)e->_line, (unsigned long)e->_column, e->_name, msg]}];
              return NO;
            }
        }
      NSString *dirAttr = e->_attributes[@"dir"];
      if (dirAttr && !([dirAttr isEqualToString: @"rtl"] || [dirAttr isEqualToString: @"ltr"]))
        {
          _error = [NSError errorWithDomain: TRMarkupErrorDomain code: 2 userInfo: @{
            NSLocalizedDescriptionKey: [NSString stringWithFormat: @"%@:%lu:%lu: <%@ dir=\"%@\">: use ltr or rtl",
              _name, (unsigned long)e->_line, (unsigned long)e->_column, e->_name, dirAttr]}];
          return NO;
        }
      NSString *st = e->_attributes[@"style"];
      NSError *err = nil;
      if (st && [st rangeOfString: @"var("].location == NSNotFound && [TRStyle styleWithDeclarations: st error: &err] == nil)
        {
          _error = [NSError errorWithDomain: TRMarkupErrorDomain code: 2 userInfo: @{
            NSLocalizedDescriptionKey: [NSString stringWithFormat: @"%@:%lu:%lu: <%@ style>: %@",
              _name, (unsigned long)e->_line, (unsigned long)e->_column, e->_name, [err localizedDescription]]}];
          return NO;
        }
    }
  return YES;
}

/* ---- CSS ---- */

- (NSArray *)parseSelector:(NSString *)sel at:(NSUInteger)pos specificity:(NSUInteger *)spec
{
  NSMutableArray *out = [NSMutableArray array];
  NSString *s = [sel stringByReplacingOccurrencesOfString: @">" withString: @" > "];
  BOOL nextIsChild = NO;
  NSUInteger a = 0, b = 0, c = 0;
  for (NSString *tok in [s componentsSeparatedByCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]])
    {
      if ([tok length] == 0) continue;
      if ([tok isEqualToString: @">"]) { nextIsChild = YES; continue; }
      TRCompound *cp = [TRCompound new];
      cp->child = nextIsChild;
      nextIsChild = NO;
      NSMutableArray *classes = [NSMutableArray array];
      NSScanner *sc = [NSScanner scannerWithString: tok];
      [sc setCharactersToBeSkipped: nil];
      NSCharacterSet *stop = [NSCharacterSet characterSetWithCharactersInString: @".#"];
      NSString *part;
      if ([sc scanUpToCharactersFromSet: stop intoString: &part])
        {
          cp->type = part;
          if (![part isEqualToString: @"*"]) c++;
        }
      while (![sc isAtEnd])
        {
          unichar k = [tok characterAtIndex: [sc scanLocation]];
          [sc setScanLocation: [sc scanLocation] + 1];
          if (![sc scanUpToCharactersFromSet: stop intoString: &part]) return nil;
          if (k == '.') { [classes addObject: part]; b++; }
          else { cp->ident = part; a++; }
        }
      if ([tok rangeOfString: @":"].location != NSNotFound || [tok rangeOfString: @"["].location != NSNotFound)
        return nil;   /* pseudo-classes and attribute selectors are not supported */
      cp->classes = classes;
      [out addObject: cp];
    }
  if ([out count] == 0 || nextIsChild || ((TRCompound *)out[0])->child) return nil;
  *spec = a * 10000 + b * 100 + c;
  return out;
}

- (BOOL)parseCSS:(NSString *)css offset:(NSUInteger)offset condition:(NSString *)cond
{
  NSUInteger i = 0, n = [css length];
  while (i < n)
    {
      /* skip whitespace and comments */
      while (i < n && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember: [css characterAtIndex: i]]) i++;
      if (i + 1 < n && [css characterAtIndex: i] == '/' && [css characterAtIndex: i + 1] == '*')
        {
          NSRange e = [css rangeOfString: @"*/" options: 0 range: NSMakeRange(i + 2, n - i - 2)];
          if (e.location == NSNotFound) return [self failAt: offset + i message: @"unterminated CSS comment"];
          i = NSMaxRange(e);
          continue;
        }
      if (i >= n) break;
      NSRange brace = [css rangeOfString: @"{" options: 0 range: NSMakeRange(i, n - i)];
      if (brace.location == NSNotFound)
        return [self failAt: offset + i message: @"expected '{' in CSS"];
      NSString *prelude = [[css substringWithRange: NSMakeRange(i, brace.location - i)]
        stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      /* find the matching close brace */
      NSUInteger depth = 0, j = brace.location;
      for (; j < n; j++)
        {
          unichar ch = [css characterAtIndex: j];
          if (ch == '{') depth++;
          else if (ch == '}' && --depth == 0) break;
        }
      if (j >= n) return [self failAt: offset + brace.location message: @"'{' is never closed"];
      NSString *body = [css substringWithRange: NSMakeRange(brace.location + 1, j - brace.location - 1)];
      NSUInteger bodyOffset = offset + brace.location + 1;

      if ([prelude hasPrefix: @"@container"])
        {
          if (cond != nil) return [self failAt: offset + i message: @"nested @container is not supported"];
          NSString *c = [[prelude substringFromIndex: 10]
            stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
          /* An optional container name before the condition is ignored. */
          NSRange paren = [c rangeOfString: @"("];
          if (paren.location != NSNotFound && paren.location > 0) c = [c substringFromIndex: paren.location];
          if (![self parseCSS: body offset: bodyOffset condition: c]) return NO;
        }
      else if ([prelude hasPrefix: @"@"])
        return [self failAt: offset + i message: @"unsupported at-rule %@", prelude];
      else
        {
          NSString *decls = [body stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
          NSError *err = nil;
          /* Custom properties, and values with var(), are checked per
             element once resolved (-validateStyles). */
          NSMutableArray *plain = [NSMutableArray array];
          for (NSArray *pair in TRSplitDeclarations(decls))
            if (!([pair count] > 1 && ([pair[0] hasPrefix: @"--"] || [pair[1] rangeOfString: @"var("].location != NSNotFound)))
              [plain addObject: pair];
          if ([TRStyle styleWithDeclarations: TRJoinDeclarations(plain) error: &err] == nil)
            return [self failAt: bodyOffset message: @"in rule '%@': %@", prelude, [err localizedDescription]];
          for (NSString *selText in [prelude componentsSeparatedByString: @","])
            {
              NSUInteger spec = 0;
              NSArray *compounds = [self parseSelector: selText at: offset + i specificity: &spec];
              if (compounds == nil)
                return [self failAt: offset + i message: @"unsupported selector '%@' (type, .class, #id, descendant and '>' only)",
                                     [selText stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
              TRRule *r = [TRRule new];
              r->compounds = compounds;
              r->declarations = decls;
              r->condition = cond;
              r->specificity = spec;
              r->order = [_rules count];
              NSUInteger l, cc;
              [self lineCol: offset + i line: &l col: &cc];
              r->line = l;
              [_rules addObject: r];
            }
        }
      i = j + 1;
    }
  return YES;
}

/* Built-in element defaults (the "user agent stylesheet"). */
static NSString *TRElementDefaults(NSString *name)
{
  static NSDictionary *d;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    d = @{
      @"column": @"flex-direction: column",
      @"row": @"flex-direction: row; align-items: center",
      @"spacer": @"flex: 1",
      @"separator": @"align-self: stretch; flex: none; min-height: 1px; min-width: 1px",
      @"scroll": @"flex: 1; min-height: 0; min-width: 0",
      @"virtual": @"flex: 1; min-height: 0; min-width: 0",
      @"split": @"flex: 1; min-height: 0; min-width: 0; align-self: stretch",
      @"progress": @"min-height: 16px; min-width: 60px",
      @"image": @"min-width: 16px; min-height: 16px",
    };
  });
  return d[name];
}

/* Conditional rules sort after unconditional ones (they are overlays
   applied after layout, on top of the base style); then specificity, then
   source order. */
static NSInteger TRCompareRules(id x, id y, void *ctx)
{
  TRRule *a = x, *b = y;
  if ((a->condition != nil) != (b->condition != nil)) return a->condition ? NSOrderedDescending : NSOrderedAscending;
  if (a->specificity != b->specificity) return a->specificity < b->specificity ? NSOrderedAscending : NSOrderedDescending;
  return a->order < b->order ? NSOrderedAscending : (a->order > b->order ? NSOrderedDescending : NSOrderedSame);
}

- (NSArray<TRMatchedDeclarations *> *)declarationsForElement:(TRMarkupElement *)e
{
  NSArray *raw = [self rawDeclarationsForElement: e];
  NSDictionary *vars = nil;
  NSMutableArray *out = [NSMutableArray arrayWithCapacity: [raw count]];
  for (__strong TRMatchedDeclarations *m in raw)
    {
      NSString *d = m->_declarations;
      if ([d rangeOfString: @"--"].location != NSNotFound || [d rangeOfString: @"var("].location != NSNotFound)
        {
          if (vars == nil) vars = [self customPropertiesForElement: e];
          TRMatchedDeclarations *r = [TRMatchedDeclarations new];
          /* An undefined variable leaves var() in place: the style then
             reports it (and -validateStyles names the element). */
          r->_declarations = [self resolveDeclarations: d vars: vars missing: NULL] ?: d;
          r->_condition = m->_condition;
          r->_line = m->_line;
          m = r;
        }
      [out addObject: m];
    }
  return out;
}

- (NSArray<TRMatchedDeclarations *> *)rawDeclarationsForElement:(TRMarkupElement *)e
{
  NSMutableArray *out = [NSMutableArray array];
  NSString *def = TRElementDefaults(e->_name);
  if (def)
    {
      TRMatchedDeclarations *m = [TRMatchedDeclarations new];
      m->_declarations = def;
      [out addObject: m];
    }
  /* dir="rtl" (HTML): direction for the element and, by inheritance, its
     content; style rules and inline styles still override it. */
  NSString *dirAttr = e->_attributes[@"dir"];
  if ([dirAttr isEqualToString: @"rtl"] || [dirAttr isEqualToString: @"ltr"])
    {
      TRMatchedDeclarations *m = [TRMatchedDeclarations new];
      m->_declarations = [@"direction: " stringByAppendingString: dirAttr];
      m->_line = e->_line;
      [out addObject: m];
    }
  NSMutableArray *matched = [NSMutableArray array];
  for (TRRule *r in _rules)
    if (TRMatchFrom(r->compounds, (NSInteger)[r->compounds count] - 1, e))
      [matched addObject: r];
  [matched sortUsingFunction: TRCompareRules context: NULL];
  for (TRRule *r in matched)
    {
      TRMatchedDeclarations *m = [TRMatchedDeclarations new];
      m->_declarations = r->declarations;
      m->_condition = r->condition;
      m->_line = r->line;
      [out addObject: m];
    }
  NSString *inl = e->_attributes[@"style"];
  if (inl)
    {
      TRMatchedDeclarations *m = [TRMatchedDeclarations new];
      m->_declarations = inl;
      m->_line = e->_line;
      /* Inline styles go before conditional overlays, after base rules. */
      NSUInteger idx = [out count];
      for (NSUInteger k = 0; k < [out count]; k++)
        if (((TRMatchedDeclarations *)out[k])->_condition != nil) { idx = k; break; }
      [out insertObject: m atIndex: idx];
    }
  return out;
}

static void TRCollectElements(TRMarkupElement *e, NSMutableArray *out)
{
  [out addObject: e];
  for (TRMarkupElement *c in e->_children) TRCollectElements(c, out);
}

- (NSArray<TRMarkupElement *> *)allElements
{
  NSMutableArray *out = [NSMutableArray array];
  if (_root) TRCollectElements(_root, out);
  for (NSString *k in [[_templates allKeys] sortedArrayUsingSelector: @selector(compare:)])
    TRCollectElements(_templates[k], out);
  return out;
}

@end
