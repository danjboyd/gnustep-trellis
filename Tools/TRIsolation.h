/* TRIsolation.h - the isolation rule trellis-render enforces on GNUstep,
   as a pure function of paths so it can be tested without touching any
   real defaults (Tests/View/isolation-verdict.m).

   A GUI run is isolated when the user defaults directory and the user
   Library both resolve inside one private directory: never the real home
   itself, an ancestor of it, or anything inside the real ~/GNUstep (where
   the real defaults live). Either
     - GNUSTEP_HOME is that private directory and the home directory,
       Library and defaults are all inside it (scripts/run-headless.sh), or
     - a GNUSTEP_CONFIG_FILE moves the defaults and Library into one
       private directory, while HOME may stay the real home.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <Foundation/Foundation.h>

/* YES if path is root or inside it (paths standardized, no trailing /). */
static inline BOOL TRPathInside(NSString *path, NSString *root)
{
  if ([path length] == 0 || [root length] == 0) return NO;
  if ([path isEqualToString: root]) return YES;
  NSString *r = [root hasSuffix: @"/"] ? root : [root stringByAppendingString: @"/"];
  return [path hasPrefix: r];
}

/* The deepest directory containing both paths. */
static inline NSString *TRCommonDirectory(NSString *a, NSString *b)
{
  NSArray *ca = [a pathComponents], *cb = [b pathComponents];
  NSMutableArray *common = [NSMutableArray array];
  for (NSUInteger i = 0; i < [ca count] && i < [cb count] && [ca[i] isEqualToString: cb[i]]; i++)
    [common addObject: ca[i]];
  return [common count] ? [NSString pathWithComponents: common] : @"";
}

/* A directory that can hold private defaults: not /, not the real home or
   an ancestor of it, and not inside the real ~/GNUstep. */
static inline BOOL TRPrivateRoot(NSString *root, NSString *realHome)
{
  if ([root length] == 0 || [root isEqualToString: @"/"]) return NO;
  if (TRPathInside(realHome, root)) return NO;
  if (TRPathInside(root, [realHome stringByAppendingPathComponent: @"GNUstep"])) return NO;
  return YES;
}

/* nil when the run is isolated, else why not. All paths standardized. */
static inline NSString *TRIsolationProblem(NSString *realHome, NSString *gnustepHome, NSString *home,
                                           NSString *userLibrary, NSString *defaultsDir, BOOL configFile)
{
  if ([userLibrary length] == 0 || [defaultsDir length] == 0)
    return @"can't find the user Library or defaults directory";
  /* The real defaults must never be reachable, whatever else holds. */
  NSString *realGS = [realHome stringByAppendingPathComponent: @"GNUstep"];
  if (TRPathInside(defaultsDir, realGS) || TRPathInside(userLibrary, realGS))
    return [NSString stringWithFormat: @"defaults (%@) or Library (%@) is inside the real %@",
                     defaultsDir, userLibrary, realGS];
  if ([gnustepHome length] && TRPrivateRoot(gnustepHome, realHome)
      && TRPathInside(home, gnustepHome) && TRPathInside(userLibrary, gnustepHome)
      && TRPathInside(defaultsDir, gnustepHome))
    return nil;
  if (configFile)
    {
      NSString *root = TRCommonDirectory(defaultsDir, userLibrary);
      if (TRPrivateRoot(root, realHome)) return nil;
      return [NSString stringWithFormat: @"GNUSTEP_CONFIG_FILE puts defaults (%@) and Library (%@) under %@, "
                       @"which isn't a private directory", defaultsDir, userLibrary, [root length] ? root : @"/"];
    }
  if ([gnustepHome length] == 0)
    return @"GNUSTEP_HOME is not set (use scripts/run-headless.sh)";
  return [NSString stringWithFormat: @"home (%@), Library (%@) or defaults (%@) is outside GNUSTEP_HOME (%@)",
                   home, userLibrary, defaultsDir, gnustepHome];
}
