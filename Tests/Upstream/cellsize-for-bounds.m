/* Reproducer: -[NSCell cellSizeForBounds:] ignores the bounds width.
   Plain Objective-C (MRC, no blocks), so it builds with GCC or clang.
   A wrapping text cell asked for its size within a 60pt-wide rect should
   report a height for several lines; libs-gui returns -cellSize (one long
   line), because NSCell.m's implementation is a TODO.

   gcc `gnustep-config --objc-flags` cellsize-for-bounds.m \
       `gnustep-config --gui-libs` -o cellsize-for-bounds
   Prints PASS or FAIL. */
#import <AppKit/AppKit.h>

int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:
    @"one two three four five six seven eight nine ten"];
  [cell setWraps: YES];
  NSSize whole = [cell cellSize];
  NSSize fit = [cell cellSizeForBounds: NSMakeRect(0, 0, 60, 10000)];
  printf("cellSize %gx%g, cellSizeForBounds(60 wide) %gx%g\n",
         whole.width, whole.height, fit.width, fit.height);
  int ok = fit.width <= 60.5 && fit.height > whole.height;
  printf(ok ? "PASS\n" : "FAIL: the width was ignored\n");
  [cell release];
  [pool release];
  return ok ? 0 : 1;
}
