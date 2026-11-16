/* Reproducer: NSSliderCell has no -cellSize of its own.
   Plain Objective-C (MRC, no blocks), so it builds with GCC or clang.
   A horizontal slider's natural height should hold its knob (Cocoa reports
   about 21pt for a regular slider); libs-gui inherits NSCell's border-only
   size, about 4pt, so layout code that trusts -cellSize clips the knob.

   gcc `gnustep-config --objc-flags` slider-cellsize.m \
       `gnustep-config --gui-libs` -o slider-cellsize
   Prints PASS or FAIL. */
#import <AppKit/AppKit.h>

int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  NSSlider *slider = [[NSSlider alloc] initWithFrame: NSMakeRect(0, 0, 200, 21)];
  NSSize s = [[slider cell] cellSize];
  CGFloat knob = [[slider cell] knobThickness];
  printf("slider cellSize %gx%g, knobThickness %g\n", s.width, s.height, knob);
  int ok = s.height >= 15;
  printf(ok ? "PASS\n" : "FAIL: the cross size can't hold a knob\n");
  [slider release];
  [pool release];
  return ok ? 0 : 1;
}
