/* The isolation rule trellis-render enforces (Tools/TRIsolation.h), on a
   synthetic stand-in tree built in a fresh temporary directory: a fake
   "real home" with its own GNUstep/Defaults, private trees, and symlinks
   that try to escape. No real home or GNUstep defaults are read or
   written. Prints ISOLATION OK. */
#import <Foundation/Foundation.h>
#import "TRIsolation.h"
#include <unistd.h>
#include <sys/stat.h>

static int gFail = 0;
static void Expect(const char *what, BOOL isolated, NSString *why)
{
  BOOL ok = isolated ? (why == nil) : (why != nil);
  printf("%s %s%s%s\n", ok ? "ok  " : "FAIL", what, why ? ": " : "", why ? [why UTF8String] : "");
  if (!ok) gFail++;
}

int main(void)
{
  @autoreleasepool
    {
      NSFileManager *fm = [NSFileManager defaultManager];
      char tmpl[] = "/tmp/trellis-isolation-XXXXXX";
      if (mkdtemp(tmpl) == NULL) { printf("ISOLATION FAIL: mkdtemp\n"); return 1; }
      NSString *T = TRResolvedPath([NSString stringWithUTF8String: tmpl]);
      NSString *(^P)(NSString *) = ^NSString *(NSString *rel) { return [T stringByAppendingPathComponent: rel]; };
      void (^mk)(NSString *) = ^(NSString *rel) {
        [fm createDirectoryAtPath: P(rel) withIntermediateDirectories: YES attributes: nil error: NULL];
      };
      void (^ln)(NSString *, NSString *) = ^(NSString *rel, NSString *target) {
        [fm createDirectoryAtPath: [P(rel) stringByDeletingLastPathComponent] withIntermediateDirectories: YES
                       attributes: nil error: NULL];
        [fm createSymbolicLinkAtPath: P(rel) withDestinationPath: P(target) error: NULL];
      };

      /* The stand-in real home, its real-looking defaults, and private trees. */
      mk(@"home/GNUstep/Defaults");
      mk(@"home/GNUstep/Library");
      mk(@"home/.cache/priv");
      mk(@"probe/gs/defaults");
      mk(@"probe/gs/lib");
      mk(@"priv");
      mk(@"priv2/Library");
      mk(@"elsewhere/defaults");
      mk(@"other");
      ln(@"esc1/gs/defaults", @"home/GNUstep/Defaults");     /* link into the real defaults */
      mk(@"esc1/gs/lib");
      ln(@"esc2/gs/lib", @"other");                          /* link out of the private tree */
      mk(@"esc2/gs/defaults");
      ln(@"sneaky", @"home/GNUstep");                        /* GNUSTEP_HOME that is really ~/GNUstep */
      ln(@"homelink", @"home");                              /* GNUSTEP_HOME that is really the home */
      mk(@"dang/gs/lib");
      ln(@"dang/gs/defaults", @"home/GNUstep/NotYetDefaults"); /* dangling: created through later */
      ln(@"dang2/gs", @"nowhere/gs");                        /* dangling link above a missing leaf */
      mk(@"locked/inner");
      chmod([P(@"locked") fileSystemRepresentation], 0);     /* can't be examined */

      NSString *real = P(@"home");
      NSString *priv = P(@"home/.cache/priv");
      Expect("run-headless layout (private dir under the real home)", YES,
             TRIsolationProblem(real, priv, priv, [priv stringByAppendingString: @"/GNUstep/Library"],
                                [priv stringByAppendingString: @"/GNUstep/Defaults"]));
      Expect("private HOME and GNUSTEP_HOME, config file moves defaults and Library inside", YES,
             TRIsolationProblem(real, P(@"probe"), P(@"probe"), P(@"probe/gs/lib"), P(@"probe/gs/defaults")));

      Expect("GNUSTEP_HOME unset", NO, TRIsolationProblem(real, @"", real, P(@"probe/gs/lib"), P(@"probe/gs/defaults")));
      Expect("only HOME changed: defaults still real (the 2026-11-11 case)", NO,
             TRIsolationProblem(real, priv, priv, [priv stringByAppendingString: @"/GNUstep/Library"],
                                P(@"home/GNUstep/Defaults")));
      Expect("config sends the defaults outside the private tree", NO,
             TRIsolationProblem(real, P(@"probe"), P(@"probe"), P(@"probe/gs/lib"), P(@"elsewhere/defaults")));
      Expect("config sends the Library outside the private tree", NO,
             TRIsolationProblem(real, P(@"probe"), P(@"probe"), P(@"other"), P(@"probe/gs/defaults")));
      Expect("HOME outside the private tree (real home)", NO,
             TRIsolationProblem(real, P(@"probe"), real, P(@"probe/gs/lib"), P(@"probe/gs/defaults")));
      Expect("sibling prefix: priv2 is not inside priv", NO,
             TRIsolationProblem(real, P(@"priv"), P(@"priv"), P(@"priv2/Library"), P(@"priv/Defaults")));
      Expect("symlink escape: defaults link into the real ~/GNUstep/Defaults", NO,
             TRIsolationProblem(real, P(@"esc1"), P(@"esc1"), P(@"esc1/gs/lib"), P(@"esc1/gs/defaults")));
      Expect("symlink escape: Library links out of the private tree", NO,
             TRIsolationProblem(real, P(@"esc2"), P(@"esc2"), P(@"esc2/gs/lib"), P(@"esc2/gs/defaults")));
      Expect("GNUSTEP_HOME is a link to the real ~/GNUstep", NO,
             TRIsolationProblem(real, P(@"sneaky"), P(@"sneaky"), P(@"sneaky/Library"), P(@"sneaky/Defaults")));
      Expect("GNUSTEP_HOME is a link to the real home", NO,
             TRIsolationProblem(real, P(@"homelink"), P(@"homelink"), P(@"homelink/x/Library"), P(@"homelink/x/Defaults")));
      Expect("GNUSTEP_HOME is the real home", NO,
             TRIsolationProblem(real, real, real, P(@"home/GNUstep/Library"), P(@"home/GNUstep/Defaults")));
      Expect("GNUSTEP_HOME is an ancestor of the real home", NO,
             TRIsolationProblem(real, T, T, P(@"probe/gs/lib"), P(@"probe/gs/defaults")));
      Expect("GNUSTEP_HOME is /", NO,
             TRIsolationProblem(real, @"/", P(@"probe"), P(@"probe/gs/lib"), P(@"probe/gs/defaults")));
      Expect("'..' through a missing directory can't be resolved safely", NO,
             TRIsolationProblem(real, P(@"probe"), P(@"probe"), P(@"probe/gs/lib"),
                                P(@"probe/missing/../../home/GNUstep/Defaults")));
      Expect("a relative path can't be resolved safely", NO,
             TRIsolationProblem(real, P(@"probe"), P(@"probe"), @"gs/lib", P(@"probe/gs/defaults")));
      Expect("dangling symlink into the real ~/GNUstep (missing target)", NO,
             TRIsolationProblem(real, P(@"dang"), P(@"dang"), P(@"dang/gs/lib"), P(@"dang/gs/defaults")));
      Expect("dangling symlink above a missing component", NO,
             TRIsolationProblem(real, P(@"dang2"), P(@"dang2"), P(@"dang2/gs/lib"), P(@"dang2/gs/defaults")));
      Expect("a missing component that isn't a link is fine", YES,
             TRIsolationProblem(real, P(@"probe"), P(@"probe"), P(@"probe/gs/lib/new/deeper"), P(@"probe/gs/not-yet")));
      if (getuid() != 0)
        Expect("an inaccessible directory can't be examined", NO,
               TRIsolationProblem(real, P(@"locked"), P(@"locked"), P(@"locked/inner/lib"), P(@"locked/inner/defaults")));
      Expect("missing Library", NO, TRIsolationProblem(real, P(@"probe"), P(@"probe"), nil, P(@"probe/gs/defaults")));

      chmod([P(@"locked") fileSystemRepresentation], 0755);
      [fm removeItemAtPath: T error: NULL];
      printf("%s\n", gFail ? "ISOLATION FAIL" : "ISOLATION OK");
    }
  return gFail ? 1 : 0;
}
