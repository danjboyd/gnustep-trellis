/* Headless check of the dev hot-reload: edit a loaded .trellis file and
   the box is rebuilt in place, its outlets re-bound to the owner; a broken
   edit keeps the old layout. Prints HOTRELOAD OK. */
#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"

@interface HROwner : NSObject
@property (nonatomic, strong) NSTextField *title;
@property (nonatomic) int reloads;
@end
@implementation HROwner
- (void)trellisDidReload:(TRBoxView *)newRoot { (void)newRoot; self.reloads++; }
@end

static int gFail = 0;
static void Expect(const char *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok) gFail++;
}

static void Write(NSString *path, NSString *title, NSString *width)
{
  NSString *s = [NSString stringWithFormat:
    @"<column><label id=\"title\">%@</label><box style=\"width: %@\"/></column>\n", title, width];
  [s writeToFile: path atomically: YES encoding: NSUTF8StringEncoding error: NULL];
}

int main(void)
{
  @autoreleasepool
    {
#ifdef GNUSTEP
      [NSApplication sharedApplication];
#endif
      NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat: @"trellis-hot-reload-%d", (int)getpid()]];
      [[NSFileManager defaultManager] createDirectoryAtPath: dir withIntermediateDirectories: YES
                                                 attributes: nil error: NULL];
      NSString *path = [dir stringByAppendingPathComponent: @"Screen.trellis"];
      Write(path, @"Before", @"40px");

      [TRLoader setHotReloadEnabled: YES];
      HROwner *owner = [HROwner new];
      NSError *err = nil;
      TRBoxView *box = [TRLoader loadFile: path owner: owner error: &err];
      if (box == nil) { printf("load failed: %s\n", [[err localizedDescription] UTF8String]); return 2; }
      NSView *host = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)];
      [box setFrame: NSMakeRect(10, 10, 280, 180)];
      [host addSubview: box];
      [box layoutTrellis];
      NSTextField *oldTitle = owner.title;

      Expect("nothing to reload before an edit", [TRLoader reloadChangedFiles] == 0);

      Write(path, @"After", @"120px");
      Expect("one box rebuilt after the edit", [TRLoader reloadChangedFiles] == 1);
      TRBoxView *now = [[host subviews] firstObject];
      Expect("the host holds a new box", [[host subviews] count] == 1 && now != box);
      Expect("the new box keeps the old frame", NSEqualRects([now frame], NSMakeRect(10, 10, 280, 180)));
      Expect("the outlet is re-bound to the new label",
             owner.title != oldTitle && [[owner.title stringValue] isEqualToString: @"After"]);
      Expect("the owner got trellisDidReload:", owner.reloads == 1);
      NSView *inner = [[now subviews] lastObject];
      Expect("the new layout is applied (box 120 wide)", fabs([inner frame].size.width - 120) < 0.5);

      [@"<column><label id=\"title\">Broken" writeToFile: path atomically: YES
                                                encoding: NSUTF8StringEncoding error: NULL];
      Expect("a broken edit rebuilds nothing", [TRLoader reloadChangedFiles] == 0);
      Expect("a broken edit keeps the current box", [[host subviews] firstObject] == now);

      Write(path, @"Fixed", @"60px");
      Expect("fixing the file reloads again", [TRLoader reloadChangedFiles] == 1
             && [[owner.title stringValue] isEqualToString: @"Fixed"]);

      [TRLoader setHotReloadEnabled: NO];
      Write(path, @"Ignored", @"60px");
      Expect("nothing reloads once it's off", [TRLoader reloadChangedFiles] == 0);

      [[NSFileManager defaultManager] removeItemAtPath: dir error: NULL];
      printf(gFail ? "HOTRELOAD FAIL\n" : "HOTRELOAD OK\n");
      return gFail ? 1 : 0;
    }
}
