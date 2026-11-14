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
    }
  return self;
}
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
  TRMarkupElement *_root;
  NSMutableDictionary *_templates;
  NSMutableArray *_rules;
  NSString *_owner;
  NSError *_error;
}
@end

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
- (NSString *)ownerClassName { return _owner; }

/* ---- Errors with line:column ---- */

- (void)lineCol:(NSUInteger)pos line:(NSUInteger *)line col:(NSUInteger *)col
{
  NSUInteger l = 1, c = 1;
  for (NSUInteger i = 0; i < pos && i < _len; i++)
    {
      if ([_src characterAtIndex: i] == '\n') { l++; c = 1; }
      else c++;
    }
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
        [top->_text appendString: TRDecodeEntities(t)];
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
      NSString *st = e->_attributes[@"style"];
      NSError *err = nil;
      if (st && [TRStyle styleWithDeclarations: st error: &err] == nil)
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
          if ([TRStyle styleWithDeclarations: decls error: &err] == nil)
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
  NSMutableArray *out = [NSMutableArray array];
  NSString *def = TRElementDefaults(e->_name);
  if (def)
    {
      TRMatchedDeclarations *m = [TRMatchedDeclarations new];
      m->_declarations = def;
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
