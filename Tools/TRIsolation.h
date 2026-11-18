/* TRIsolation.h - the isolation rule trellis-render enforces on GNUstep,
   as a function of paths so it can be tested on synthetic stand-in trees
   without touching any real defaults (Tests/View/isolation-verdict.m).

   A GUI run is isolated when GNUSTEP_HOME is a private directory and the
   home directory, the effective user Library and the effective user
   defaults directory (as gnustep-base reports them, so a
   GNUSTEP_CONFIG_FILE is honoured) all resolve inside it. Resolving
   follows symlinks, so a link out of the private tree is caught, and
   containment is checked component by component, so /tmp/priv2 is not
   inside /tmp/priv. A private directory is not /, not the real home or
   an ancestor of it, and not inside the real ~/GNUstep, the real home
   coming from the password database. A path that can't be resolved
   safely fails the check.

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <limits.h>
#include <errno.h>
#include <sys/stat.h>

/* path with symlinks resolved: the deepest existing ancestor through
   realpath(3), then the components that don't exist yet (which can hold
   no links). nil if path is empty or relative, if a missing component is
   "." or "..", if any component is a dangling symlink or can't be
   examined (anything but ENOENT), or if realpath fails. */
static inline NSString *TRResolvedPath(NSString *path)
{
  if ([path length] == 0 || ![path isAbsolutePath]) return nil;
  NSMutableArray *rest = [NSMutableArray array];
  NSString *cur = path;
  NSFileManager *fm = [NSFileManager defaultManager];
  struct stat st;
  while (stat([cur fileSystemRepresentation], &st) != 0)
    {
      /* Only a component that doesn't exist at all counts as missing. A
         dangling symlink (lstat succeeds) could be created through later,
         and an inaccessible path can't be checked: both fail. */
      if (errno != ENOENT || lstat([cur fileSystemRepresentation], &st) == 0) return nil;
      NSString *last = [cur lastPathComponent];
      if ([last isEqualToString: @".."] || [last isEqualToString: @"."]) return nil;
      [rest insertObject: last atIndex: 0];
      NSString *up = [cur stringByDeletingLastPathComponent];
      if ([up isEqualToString: cur] || [up length] == 0) return nil;
      cur = up;
    }
  char buf[PATH_MAX];
  if (realpath([cur fileSystemRepresentation], buf) == NULL) return nil;
  NSString *r = [fm stringWithFileSystemRepresentation: buf length: strlen(buf)];
  for (NSString *c in rest) r = [r stringByAppendingPathComponent: c];
  return r;
}

/* YES if path is root or inside it, comparing whole components. */
static inline BOOL TRPathInside(NSString *path, NSString *root)
{
  if ([path length] == 0 || [root length] == 0) return NO;
  NSArray *p = [path pathComponents], *r = [root pathComponents];
  if ([r count] > [p count]) return NO;
  for (NSUInteger i = 0; i < [r count]; i++)
    if (![p[i] isEqualToString: r[i]]) return NO;
  return YES;
}

/* nil when the run is isolated, else why not. Paths as the process sees
   them; they are resolved here. */
static inline NSString *TRIsolationProblem(NSString *realHomeIn, NSString *gnustepHomeIn, NSString *homeIn,
                                           NSString *userLibraryIn, NSString *defaultsDirIn)
{
  if ([gnustepHomeIn length] == 0) return @"GNUSTEP_HOME is not set";
  NSString *realHome = TRResolvedPath(realHomeIn), *gh = TRResolvedPath(gnustepHomeIn);
  NSString *home = TRResolvedPath(homeIn), *lib = TRResolvedPath(userLibraryIn);
  NSString *defaults = TRResolvedPath(defaultsDirIn);
  if (!realHome || !gh || !home || !lib || !defaults)
    return [NSString stringWithFormat: @"can't resolve the real home (%@), GNUSTEP_HOME (%@), home (%@), "
                     @"Library (%@) or defaults (%@) safely", realHomeIn, gnustepHomeIn, homeIn,
                     userLibraryIn, defaultsDirIn];
  NSString *realGS = TRResolvedPath([realHome stringByAppendingPathComponent: @"GNUstep"]);
  if (!realGS) return @"can't resolve the real ~/GNUstep safely";
  if ([gh isEqualToString: @"/"] || TRPathInside(realHome, gh) || TRPathInside(gh, realGS))
    return [NSString stringWithFormat: @"GNUSTEP_HOME (%@) is not a private directory: it is /, the real "
                     @"home or above it, or inside the real %@", gh, realGS];
  if (TRPathInside(defaults, realGS) || TRPathInside(lib, realGS))
    return [NSString stringWithFormat: @"defaults (%@) or Library (%@) is inside the real %@", defaults, lib, realGS];
  if (!TRPathInside(home, gh) || !TRPathInside(lib, gh) || !TRPathInside(defaults, gh))
    return [NSString stringWithFormat: @"home (%@), Library (%@) or defaults (%@) is outside GNUSTEP_HOME (%@)",
                     home, lib, defaults, gh];
  return nil;
}
