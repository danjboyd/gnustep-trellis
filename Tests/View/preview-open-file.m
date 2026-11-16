/* Headless check for Trellis Preview: a .trellis path on the command line
   must not reach NSDocumentController (GNUstep 0.32 showed an empty modal
   "Alert" before the window). Builds TPController.m with its main renamed,
   runs -finishLaunching (where GNUstep opens command-line files) and fails
   if an alert panel exists. A modal alert would hang it: run with a
   timeout under scripts/run-headless.sh. Prints OPENFILE OK. */
#define main tp_preview_main
#include "../../Tools/TrellisPreview/TPController.m"
#undef main

int main(int argc, const char **argv)
{
  @autoreleasepool
    {
      if (argc < 2) { fprintf(stderr, "usage: preview-open-file FILE.trellis\n"); return 2; }
      [NSApplication sharedApplication];
      TPController *c = [[TPController alloc] initWithPath: nil snapshot: nil
                                                      size: NSMakeSize(400, 300) inspector: NO];
      [NSApp setDelegate: c];
      [NSApp finishLaunching];
      int alerts = 0;
      for (NSWindow *w in [NSApp windows])
        if ([w isKindOfClass: [NSPanel class]] && [w isVisible]
            && [[w title] rangeOfString: @"Alert"].location != NSNotFound)
          alerts++;
      NSString *path = [c valueForKey: @"_path"];
      BOOL ok = alerts == 0 && [path hasSuffix: [[NSString stringWithUTF8String: argv[1]] lastPathComponent]];
      printf("path=%s alerts=%d\n", [path UTF8String] ?: "(nil)", alerts);
      printf(ok ? "OPENFILE OK\n" : "OPENFILE FAIL\n");
      return ok ? 0 : 1;
    }
}
