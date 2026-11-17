/* Custom properties in .trellis files: --name declarations, var() with
   fallbacks, inheritance, built-in tokens, @container-local values,
   templates, and the errors. Prints CUSTOMPROPS OK. */
#import <Foundation/Foundation.h>
#import "TRMarkup.h"
#import "TRStyle.h"

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok) gFail++;
}

static TRMarkupElement *Find(TRMarkupDocument *d, NSString *ident)
{
  for (TRMarkupElement *e in [d allElements]) if ([[e identifier] isEqualToString: ident]) return e;
  return nil;
}

/* The element's resolved unconditional style. */
static TRStyle *StyleOf(TRMarkupDocument *d, NSString *ident)
{
  TRStyle *st = [TRStyle new];
  for (TRMatchedDeclarations *m in [d declarationsForElement: Find(d, ident)])
    if (m.condition == nil && ![st applyDeclarations: m.declarations error: NULL])
      printf("     bad: %s\n", [m.declarations UTF8String]);
  return st;
}

static NSString *Conditional(TRMarkupDocument *d, NSString *ident)
{
  for (TRMatchedDeclarations *m in [d declarationsForElement: Find(d, ident)])
    if (m.condition) return m.declarations;
  return nil;
}

static NSString *Fails(NSString *src)
{
  NSError *err = nil;
  TRMarkupDocument *d = [TRMarkupDocument documentWithString: src name: @"t.trellis" error: &err];
  return d ? nil : [err localizedDescription];
}

int main(void)
{
  @autoreleasepool
    {
      NSString *src =
        @"<column id=\"app\" class=\"app\">\n"
        @"  <row id=\"bar\" class=\"bar\"><label id=\"title\" class=\"title\">T</label></row>\n"
        @"  <column id=\"card\" class=\"card dense\"><label id=\"inner\" class=\"pad\">I</label></column>\n"
        @"  <label id=\"tok\" class=\"tok\">B</label>\n"
        @"  <label id=\"fb\" class=\"fb\">F</label>\n"
        @"</column>\n"
        @"<template id=\"row\"><row id=\"trow\" class=\"pad\"><label>R</label></row></template>\n"
        @"<style>\n"
        @"  .app   { --gap: 8px; --pad: var(--gap); --brand: #3366cc; gap: var(--gap); }\n"
        @"  .bar   { padding: var(--pad) calc0; }\n"
        @"  .title { color: var(--brand); font-size: var(--tr-title-font-size); }\n"
        @"  .card  { --gap: 2px; gap: var(--gap); }\n"
        @"  .dense { --pad: 1px; }\n"
        @"  .pad   { padding: var(--pad); }\n"
        @"  .tok   { padding: var(--tr-space-m); border-radius: var(--tr-radius); color: var(--tr-muted); }\n"
        @"  .fb    { padding: var(--nope, var(--also-nope, 3px)); }\n"
        @"  @container (max-width: 400px) { .app { --gap: 20px; gap: var(--gap); } .pad { padding: var(--gap); } }\n"
        @"</style>\n";
      src = [src stringByReplacingOccurrencesOfString: @" calc0" withString: @""];
      NSError *err = nil;
      TRMarkupDocument *d = [TRMarkupDocument documentWithString: src name: @"vars.trellis" error: &err];
      if (d == nil) { printf("parse failed: %s\nCUSTOMPROPS FAIL\n", [[err localizedDescription] UTF8String]); return 1; }

      Expect("var() on the defining element", TRValueEqual(StyleOf(d, @"app").rowGap, TRPx(8)));
      Expect("inherits to descendants", TRValueEqual([StyleOf(d, @"bar") paddingForEdge: TREdgeTop], TRPx(8)));
      Expect("a custom property's own var() resolves where defined",
             TRValueEqual([StyleOf(d, @"inner") paddingForEdge: TREdgeLeft], TRPx(1)));
      Expect("redefined on a descendant", TRValueEqual(StyleOf(d, @"card").rowGap, TRPx(2)));
      Expect("colour through var()", [StyleOf(d, @"title").otherDeclarations[@"color"] isEqualToString: @"#3366cc"]);
      NSString *tfs = StyleOf(d, @"title").otherDeclarations[@"font-size"];
      Expect("built-in token (--tr-title-font-size)", [tfs hasSuffix: @"px"] && [tfs doubleValue] > 10);
      TRStyle *tok = StyleOf(d, @"tok");
      Expect("built-in spacing, radius and colour tokens",
             TRValueEqual([tok paddingForEdge: TREdgeTop], TRPx(8))
             && [tok.otherDeclarations[@"border-radius"] isEqualToString: @"6px"]
             && [tok.otherDeclarations[@"color"] isEqualToString: @"GrayText"]);
      Expect("nested fallbacks", TRValueEqual([StyleOf(d, @"fb") paddingForEdge: TREdgeTop], TRPx(3)));
      NSString *cond = Conditional(d, @"app");
      Expect("@container block uses its own --gap", [cond rangeOfString: @"20px"].location != NSNotFound
             && [cond rangeOfString: @"--gap"].location == NSNotFound);
      NSString *innerCond = Conditional(d, @"inner");
      Expect("...which doesn't inherit (descendant sees the base --gap 2px)",
             innerCond && [innerCond rangeOfString: @"2px"].location != NSNotFound);
      Expect("a top-level template sees the root's properties",
             TRValueEqual([StyleOf(d, @"trow") paddingForEdge: TREdgeTop], TRPx(8)));
      Expect("custom properties come back stripped",
             [[[d declarationsForElement: Find(d, @"app")] valueForKey: @"declarations"]
               indexOfObjectPassingTest: ^BOOL (NSString *s, NSUInteger i, BOOL *stop) {
                 return [s rangeOfString: @"--"].location != NSNotFound; }] == NSNotFound);
      Expect("customPropertiesForElement includes built-ins and own",
             [[d customPropertiesForElement: Find(d, @"card")][@"--gap"] isEqualToString: @"2px"]
             && [d customPropertiesForElement: Find(d, @"card")][@"--tr-radius"] != nil);

      /* Built-ins can be replaced (the AppKit layer does, from the theme). */
      NSMutableDictionary *b = [[TRMarkupDocument defaultBuiltinCustomProperties] mutableCopy];
      b[@"--tr-space-m"] = @"9px";
      [TRMarkupDocument setBuiltinCustomProperties: b];
      TRMarkupDocument *d2 = [TRMarkupDocument documentWithString: src name: @"vars2.trellis" error: &err];
      Expect("replaced built-in tokens apply", TRValueEqual([StyleOf(d2, @"tok") paddingForEdge: TREdgeTop], TRPx(9)));
      [TRMarkupDocument setBuiltinCustomProperties: [TRMarkupDocument defaultBuiltinCustomProperties]];

      /* Errors name the element. */
      NSString *e1 = Fails(@"<column><label class=\"x\">A</label></column><style>.x { padding: var(--missing); }</style>");
      Expect("undefined var() is an error at the element",
             e1 && [e1 rangeOfString: @"var(--missing) is not defined"].location != NSNotFound
             && [e1 rangeOfString: @"t.trellis:1:"].location != NSNotFound);
      NSString *e2 = Fails(@"<column class=\"c\"><label class=\"x\">A</label></column>"
                           @"<style>.c { --w: wide; } .x { width: var(--w); }</style>");
      Expect("a bad value after substitution is an error", e2 && [e2 rangeOfString: @"after var()"].location != NSNotFound);
      NSString *e3 = Fails(@"<column class=\"c\"><label class=\"x\">A</label></column>"
                           @"<style>.c { --a: var(--b); --b: var(--a); } .x { width: var(--a); }</style>");
      Expect("a cycle is an error, not a hang", e3 != nil);
      Expect("a declared but unused custom property is fine",
             Fails(@"<column class=\"c\"></column><style>.c { --unused: 4px; }</style>") == nil);
    }
  printf(gFail ? "CUSTOMPROPS FAIL\n" : "CUSTOMPROPS OK\n");
  return gFail ? 1 : 0;
}
