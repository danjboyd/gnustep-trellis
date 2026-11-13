/* TRContainerQuery.m - CSS container queries (width conditions).

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRNode+Internal.h"

@interface TRCondition : NSObject
{
@public
  NSString *text;
  NSString *declarations;
  TRFloat min, max;          /* NAN = unbounded */
  BOOL minStrict, maxStrict;
}
@end
@implementation TRCondition
@end

static NSError *TRCQError(NSString *msg)
{
  return [NSError errorWithDomain: TRStyleErrorDomain code: 3
                         userInfo: @{NSLocalizedDescriptionKey: msg}];
}

static BOOL TRParsePx(NSString *s, TRFloat *out)
{
  s = [[s stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]] lowercaseString];
  if ([s hasSuffix: @"px"]) s = [s substringToIndex: [s length] - 2];
  NSScanner *sc = [NSScanner scannerWithString: s];
  double d;
  if (![sc scanDouble: &d] || ![sc isAtEnd]) return NO;
  *out = d;
  return YES;
}

static TRCondition *TRParseCondition(NSString *cond, NSError **error)
{
  TRCondition *c = [TRCondition new];
  c->text = [cond copy];
  c->min = c->max = TRUndefined;
  NSString *s = [[cond lowercaseString] stringByReplacingOccurrencesOfString: @"(" withString: @" "];
  s = [s stringByReplacingOccurrencesOfString: @")" withString: @" "];
  for (NSString *raw in [s componentsSeparatedByString: @" and "])
    {
      NSString *part = [raw stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
      if ([part length] == 0) continue;
      TRFloat v;
      NSRange colon = [part rangeOfString: @":"];
      if (colon.location != NSNotFound)
        {
          NSString *k = [[part substringToIndex: colon.location]
            stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
          if (!TRParsePx([part substringFromIndex: NSMaxRange(colon)], &v)) goto bad;
          if ([k isEqualToString: @"min-width"]) c->min = v;
          else if ([k isEqualToString: @"max-width"]) c->max = v;
          else goto bad;
          continue;
        }
      if (![part hasPrefix: @"width"]) goto bad;
      NSString *rest = [[part substringFromIndex: 5]
        stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
      if ([rest hasPrefix: @">="]) { if (!TRParsePx([rest substringFromIndex: 2], &v)) goto bad; c->min = v; }
      else if ([rest hasPrefix: @"<="]) { if (!TRParsePx([rest substringFromIndex: 2], &v)) goto bad; c->max = v; }
      else if ([rest hasPrefix: @">"]) { if (!TRParsePx([rest substringFromIndex: 1], &v)) goto bad; c->min = v; c->minStrict = YES; }
      else if ([rest hasPrefix: @"<"]) { if (!TRParsePx([rest substringFromIndex: 1], &v)) goto bad; c->max = v; c->maxStrict = YES; }
      else goto bad;
    }
  if (isnan(c->min) && isnan(c->max)) goto bad;
  return c;
bad:
  if (error) *error = TRCQError([NSString stringWithFormat: @"cannot parse container condition \"%@\"", cond]);
  return nil;
}

static BOOL TRConditionMatches(TRCondition *c, TRFloat w)
{
  if (!isnan(c->min) && (c->minStrict ? !(w > c->min) : !(w >= c->min - 0.0001))) return NO;
  if (!isnan(c->max) && (c->maxStrict ? !(w < c->max) : !(w <= c->max + 0.0001))) return NO;
  return YES;
}

@implementation TRNode (ContainerQueries)

- (BOOL)addConditionalStyle:(NSString *)declarations when:(NSString *)condition error:(NSError **)error
{
  TRCondition *c = TRParseCondition(condition, error);
  if (c == nil) return NO;
  /* Validate the declarations now, so errors surface at the call. */
  if ([TRStyle styleWithDeclarations: declarations error: error] == nil) return NO;
  if (_conditions == nil)
    {
      _conditions = [NSMutableArray array];
      _baseStyle = [_style copy];
    }
  if ([_conditions count] >= 64)
    {
      if (error) *error = TRCQError(@"at most 64 container conditions per node");
      return NO;
    }
  c->declarations = [declarations copy];
  [_conditions addObject: c];
  [self markDirty];
  return YES;
}

- (NSArray<NSString *> *)matchedConditions
{
  NSMutableArray *out = [NSMutableArray array];
  for (NSUInteger i = 0; i < [_conditions count]; i++)
    if (_matchedMask & (1ULL << i))
      [out addObject: ((TRCondition *)_conditions[i])->text];
  return out;
}

@end

static BOOL TRIsContainer(TRNode *n)
{
  NSString *t = [n->_style otherDeclarations][@"container-type"];
  return t != nil && ![t isEqualToString: @"normal"];
}

static BOOL TRApply(TRNode *n, TRNode *root)
{
  BOOL changed = NO;
  if (n->_conditions != nil)
    {
      TRNode *c = n->_parent;
      while (c != nil && !TRIsContainer(c)) c = c->_parent;
      if (c == nil) c = root;
      TRFloat w = c->_rawFrame.width - c->_lpad[TREdgeLeft] - c->_lpad[TREdgeRight]
                - c->_lborder[TREdgeLeft] - c->_lborder[TREdgeRight];
      uint64_t mask = 0;
      for (NSUInteger i = 0; i < [n->_conditions count]; i++)
        if (TRConditionMatches(n->_conditions[i], w)) mask |= (1ULL << i);
      if (mask != n->_matchedMask)
        {
          n->_matchedMask = mask;
          TRStyle *st = [n->_baseStyle copy];
          for (NSUInteger i = 0; i < [n->_conditions count]; i++)
            if (mask & (1ULL << i))
              [st applyDeclarations: ((TRCondition *)n->_conditions[i])->declarations error: NULL];
          st.owner = n;
          n->_style = st;
          [n markDirty];
          changed = YES;
        }
    }
  for (TRNode *child in n->_children)
    changed |= TRApply(child, root);
  return changed;
}

BOOL TRApplyContainerQueries(TRNode *root)
{
  return TRApply(root, root);
}
