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
        [outlets addObject: [body substringWithRange: [p rangeAtIndex: 1]]];
      for (NSTextCheckingResult *p in [meth matchesInString: body options: 0 range: all])
        [actions addObject: [[body substringWithRange: [p rangeAtIndex: 1]] stringByAppendingString: @":"]];
      *foundClass = name;
      found = YES;
      if (cls == nil) break;
    }
  return found;
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
  NSMutableSet *ids = [NSMutableSet set];
  for (TRMarkupElement *e in [doc allElements])
    {
      NSString *ident = [e identifier];
      NSString *where = [NSString stringWithFormat: @"%@:%lu:%lu", path, (unsigned long)e.line, (unsigned long)e.column];
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
