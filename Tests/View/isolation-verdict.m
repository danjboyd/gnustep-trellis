/* The isolation rule trellis-render enforces (Tools/TRIsolation.h), on
   synthetic paths only: no GNUstep defaults are read or written. Prints
   ISOLATION OK. */
#import <Foundation/Foundation.h>
#import "TRIsolation.h"

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
      NSString *real = @"/home/user";
      NSString *priv = @"/home/user/.cache/trellis-gnustep-home";
      /* scripts/run-headless.sh: GNUSTEP_HOME and HOME private, defaults default. */
      Expect("run-headless layout", YES,
             TRIsolationProblem(real, priv, priv, [priv stringByAppendingString: @"/GNUstep/Library"],
                                [priv stringByAppendingString: @"/GNUstep/Defaults"], NO));
      /* AIManager's harness: HOME and GNUSTEP_HOME real, config file moves defaults and Library. */
      Expect("config file, real HOME, private gs dir", YES,
             TRIsolationProblem(real, @"", real, @"/tmp/probe/gs/lib", @"/tmp/probe/gs/defaults", YES));
      /* ...and the same config under run-headless (GNUSTEP_HOME private but elsewhere). */
      Expect("config file under run-headless", YES,
             TRIsolationProblem(real, priv, priv, @"/tmp/probe/gs/lib", @"/tmp/probe/gs/defaults", YES));
      /* Refusals. */
      Expect("nothing set: real home and real defaults", NO,
             TRIsolationProblem(real, @"", real, @"/home/user/GNUstep/Library", @"/home/user/GNUstep/Defaults", NO));
      Expect("only HOME changed: defaults still real (the 2026-11-11 case)", NO,
             TRIsolationProblem(real, @"", @"/tmp/h", @"/tmp/h/GNUstep/Library", @"/home/user/GNUstep/Defaults", NO));
      Expect("GNUSTEP_HOME is the real home", NO,
             TRIsolationProblem(real, real, real, @"/home/user/GNUstep/Library", @"/home/user/GNUstep/Defaults", NO));
      Expect("GNUSTEP_HOME is /", NO,
             TRIsolationProblem(real, @"/", @"/tmp/x", @"/tmp/x/GNUstep/Library", @"/tmp/x/GNUstep/Defaults", NO));
      Expect("config file keeps real defaults", NO,
             TRIsolationProblem(real, @"", real, @"/tmp/probe/gs/lib", @"/home/user/GNUstep/Defaults", YES));
      Expect("config file keeps real Library", NO,
             TRIsolationProblem(real, @"", real, @"/home/user/GNUstep/Library", @"/tmp/probe/gs/defaults", YES));
      Expect("config file: common directory is the real home", NO,
             TRIsolationProblem(real, @"", real, @"/home/user/a/lib", @"/home/user/b/defaults", YES));
      Expect("config file: common directory is /", NO,
             TRIsolationProblem(real, @"", real, @"/tmp/lib", @"/var/defaults", YES));
      Expect("private dir inside real ~/GNUstep", NO,
             TRIsolationProblem(real, @"/home/user/GNUstep/private", @"/home/user/GNUstep/private",
                                @"/home/user/GNUstep/private/GNUstep/Library",
                                @"/home/user/GNUstep/private/GNUstep/Defaults", NO));
      Expect("a sibling with a common prefix isn't inside", NO,
             TRIsolationProblem(real, @"/tmp/priv", @"/tmp/priv", @"/tmp/priv2/Library", @"/tmp/priv/Defaults", NO));
      Expect("missing Library", NO, TRIsolationProblem(real, priv, priv, nil, @"/x", NO));
      printf("%s\n", gFail ? "ISOLATION FAIL" : "ISOLATION OK");
    }
  return gFail ? 1 : 0;
}
