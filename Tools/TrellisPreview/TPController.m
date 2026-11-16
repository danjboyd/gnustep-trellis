/* TPController.m - Trellis Preview: open a .trellis file, watch it, show it.

   - Live reload: the file (and Name.sample.json) are polled twice a second.
   - Resize the window to see the layout respond; View > Width presets.
   - View > Inspector draws box outlines and lint findings over the screen.
   - Theme menu (GNUstep: any installed GSTheme; macOS: light/dark).
   - Unknown custom view classes show as labelled placeholders.
   - Load errors (with file:line:col) replace the screen until fixed.

   --snapshot out.png [--width W --height H] [--inspector] renders once and
   exits (used for headless checks).

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <AppKit/AppKit.h>
#import "TRBoxView.h"
#import "TRLoader.h"
#import "TRViewMeasure.h"
#import "TRLint.h"
#ifdef GNUSTEP
#import <GNUstepGUI/GSTheme.h>
#endif

/* ---- Overlay ---- */

@interface TPOverlay : NSView
@property (nonatomic, weak) NSView *target;
@property (nonatomic, copy) NSArray *findings;   /* lint dictionaries with "path" */
@end

@implementation TPOverlay
- (BOOL)isFlipped { return YES; }
- (NSView *)hitTest:(NSPoint)p { return nil; }   /* clicks go through */

static void TPOutline(NSView *v, NSView *overlay)
{
  if ([v isHidden]) return;
  NSRect r = [overlay convertRect: [v bounds] fromView: v];
  BOOL box = [v isKindOfClass: [TRBoxView class]];
  [(box ? [NSColor colorWithCalibratedRed: 0.1 green: 0.45 blue: 0.85 alpha: 0.7]
        : [NSColor colorWithCalibratedRed: 0.9 green: 0.35 blue: 0.1 alpha: 0.6]) set];
  NSFrameRectWithWidth(r, 1);
  NSArray *subs = [v isKindOfClass: [NSScrollView class]] ? @[[(NSScrollView *)v documentView]] : [v subviews];
  if (box || [v isKindOfClass: [NSScrollView class]])
    for (NSView *c in subs) TPOutline(c, overlay);
}

/* Resolves a lint path ("root/1/0") to a view. */
static NSView *TPViewAtPath(NSView *root, NSString *path)
{
  NSArray *parts = [path componentsSeparatedByString: @"/"];
  NSView *v = root;
  for (NSUInteger i = 1; i < [parts count] && v != nil; i++)
    {
      NSArray *kids;
      if ([v isKindOfClass: [TRScrollBox class]]) kids = @[[(TRScrollBox *)v contentBox]];
      else if ([v isKindOfClass: [TRBoxView class]])
        {
          NSMutableArray *k = [NSMutableArray array];
          for (TRNode *n in [(TRBoxView *)v node].children) if (n.context) [k addObject: n.context];
          kids = k;
        }
      else return nil;
      NSInteger idx = [parts[i] integerValue];
      v = idx < (NSInteger)[kids count] ? kids[idx] : nil;
    }
  return v;
}

- (void)drawRect:(NSRect)dirty
{
  NSView *t = self.target;
  if (t == nil) return;
  TPOutline(t, self);
  NSDictionary *attrs = @{NSFontAttributeName: [NSFont systemFontOfSize: 10],
                          NSForegroundColorAttributeName: [NSColor whiteColor]};
  for (NSDictionary *f in self.findings)
    {
      NSView *v = TPViewAtPath(t, f[@"path"]);
      if (v == nil) continue;
      NSRect r = [self convertRect: [v bounds] fromView: v];
      BOOL err = [f[@"severity"] isEqualToString: @"error"];
      [(err ? [NSColor colorWithCalibratedRed: 0.85 green: 0.1 blue: 0.1 alpha: 0.9]
            : [NSColor colorWithCalibratedRed: 0.9 green: 0.6 blue: 0 alpha: 0.9]) set];
      NSFrameRectWithWidth(r, 2);
      NSString *tag = f[@"rule"];
      NSSize ts = [tag sizeWithAttributes: attrs];
      NSRect tr = NSMakeRect(NSMinX(r), NSMinY(r), ts.width + 6, ts.height + 2);
      NSRectFill(tr);
      [tag drawAtPoint: NSMakePoint(NSMinX(tr) + 3, NSMinY(tr) + 1) withAttributes: attrs];
    }
}
@end

/* ---- Content view: hosts the screen and the overlay ---- */

@interface TPContentView : NSView
@end
@implementation TPContentView
- (BOOL)isFlipped { return YES; }
@end

/* ---- Controller ---- */

@interface TPController : NSObject <NSApplicationDelegate, NSWindowDelegate>
{
  NSWindow *_window;
  TPContentView *_content;
  TPOverlay *_overlay;
  TRBoxView *_screen;
  NSTextField *_errorLabel;
  NSString *_path;
  NSDate *_mtime, *_sampleMtime;
  NSTimer *_timer;
  BOOL _inspector;
  NSString *_snapshot;
  NSSize _initialSize;
  NSArray *_findings;
}
@end

@implementation TPController

- (instancetype)initWithPath:(NSString *)path snapshot:(NSString *)snapshot size:(NSSize)size inspector:(BOOL)insp
{
  if ((self = [super init]) != nil)
    {
      _path = [path copy];
      _snapshot = [snapshot copy];
      _initialSize = size;
      _inspector = insp;
    }
  return self;
}

- (NSString *)samplePath
{
  return [[_path stringByDeletingPathExtension] stringByAppendingPathExtension: @"sample.json"];
}

static NSDate *TPModDate(NSString *path)
{
  return [[[NSFileManager defaultManager] attributesOfItemAtPath: path error: NULL] fileModificationDate];
}

- (void)buildMenu
{
  NSMenu *main = [[NSMenu alloc] initWithTitle: @"Trellis Preview"];
  NSMenu *file = [[NSMenu alloc] initWithTitle: @"File"];
  [file addItemWithTitle: @"Open…" action: @selector(openDocument:) keyEquivalent: @"o"];
  [file addItemWithTitle: @"Reload" action: @selector(reload:) keyEquivalent: @"r"];
  [file addItemWithTitle: @"Quit" action: @selector(terminate:) keyEquivalent: @"q"];
  [[main addItemWithTitle: @"File" action: NULL keyEquivalent: @""] setSubmenu: file];

  NSMenu *view = [[NSMenu alloc] initWithTitle: @"View"];
  [view addItemWithTitle: @"Inspector" action: @selector(toggleInspector:) keyEquivalent: @"i"];
  for (NSNumber *w in @[@360, @520, @800, @1200])
    {
      NSMenuItem *it = (NSMenuItem *)[view addItemWithTitle: [NSString stringWithFormat: @"Width %@", w]
                                       action: @selector(setWidthPreset:) keyEquivalent: @""];
      [it setTag: [w integerValue]];
    }
  [[main addItemWithTitle: @"View" action: NULL keyEquivalent: @""] setSubmenu: view];

  NSMenu *theme = [[NSMenu alloc] initWithTitle: @"Theme"];
#ifdef GNUSTEP
  NSMutableSet *names = [NSMutableSet setWithObject: @"GNUstep"];
  for (NSString *dir in NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSAllDomainsMask, YES))
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:
                          [dir stringByAppendingPathComponent: @"Themes"] error: NULL])
      if ([[f pathExtension] isEqualToString: @"theme"]) [names addObject: [f stringByDeletingPathExtension]];
  for (NSString *n in [[names allObjects] sortedArrayUsingSelector: @selector(compare:)])
    {
      NSMenuItem *it = (NSMenuItem *)[theme addItemWithTitle: n action: @selector(chooseTheme:) keyEquivalent: @""];
      [it setRepresentedObject: n];
    }
#else
  for (NSString *n in @[@"Light", @"Dark"])
    {
      NSMenuItem *it = (NSMenuItem *)[theme addItemWithTitle: n action: @selector(chooseTheme:) keyEquivalent: @""];
      [it setRepresentedObject: n];
    }
#endif
  [[main addItemWithTitle: @"Theme" action: NULL keyEquivalent: @""] setSubmenu: theme];
  [NSApp setMainMenu: main];
}

- (void)applicationDidFinishLaunching:(NSNotification *)n
{
  if (_snapshot == nil) [self buildMenu];
  NSRect frame = NSMakeRect(80, 80, _initialSize.width, _initialSize.height);
  _window = [[NSWindow alloc] initWithContentRect: frame
                                        styleMask: (NSTitledWindowMask | NSClosableWindowMask
                                                    | NSResizableWindowMask | NSMiniaturizableWindowMask)
                                          backing: NSBackingStoreBuffered defer: NO];
  [_window setReleasedWhenClosed: NO];
  [_window setDelegate: self];
  _content = [[TPContentView alloc] initWithFrame: [[_window contentView] frame]];
  [_content setAutoresizesSubviews: YES];
  [_window setContentView: _content];
  _overlay = [[TPOverlay alloc] initWithFrame: [_content bounds]];
  [_overlay setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  _errorLabel = [[NSTextField alloc] initWithFrame: NSInsetRect([_content bounds], 16, 16)];
  [_errorLabel setEditable: NO];
  [_errorLabel setBezeled: NO];
  [_errorLabel setDrawsBackground: NO];
  [_errorLabel setTextColor: [NSColor colorWithCalibratedRed: 0.75 green: 0 blue: 0 alpha: 1]];
  [[_errorLabel cell] setWraps: YES];
  [_errorLabel setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

  if (_path) [self reload: nil];
  else [self openDocument: nil];

  if (_snapshot)
    {
      [_content display];
      [self snapshotTo: _snapshot];
      return;
    }
  [_window makeKeyAndOrderFront: nil];
  _timer = [NSTimer scheduledTimerWithTimeInterval: 0.5 target: self selector: @selector(poll:)
                                          userInfo: nil repeats: YES];
}

/* Files handed to the app: a path on the command line (GNUstep's
   NSApplication opens those too), Finder or Dock opens on macOS. Handled
   here, so they never reach NSDocumentController, which has no document
   types for .trellis and showed an empty "Alert". At launch the window
   doesn't exist yet: the path is kept and loaded by
   -applicationDidFinishLaunching:. */
- (BOOL)application:(NSApplication *)app openFile:(NSString *)file
{
  if (![[file pathExtension] isEqualToString: @"trellis"]) return NO;
  _path = [file stringByStandardizingPath];
  _mtime = nil;
  if (_window != nil)
    {
      [self reload: nil];
      [_window makeKeyAndOrderFront: nil];
    }
  return YES;
}

- (void)application:(NSApplication *)app openFiles:(NSArray *)files
{
  BOOL ok = NO;
  for (NSString *f in files)
    if ([self application: app openFile: f]) { ok = YES; break; }
  [app replyToOpenOrPrint: ok ? NSApplicationDelegateReplySuccess : NSApplicationDelegateReplyFailure];
}

- (void)openDocument:(id)sender
{
  NSOpenPanel *p = [NSOpenPanel openPanel];
  [p setAllowedFileTypes: @[@"trellis"]];
  if ([p runModal] == NSModalResponseOK)
    {
      _path = [[[p URLs] firstObject] path];
      _mtime = nil;
      [self reload: nil];
    }
}

- (void)poll:(NSTimer *)t
{
  if (_path == nil) return;
  NSDate *m = TPModDate(_path), *sm = TPModDate([self samplePath]);
  if ((m && ![m isEqual: _mtime]) || (sm && ![sm isEqual: _sampleMtime]))
    [self reload: nil];
}

- (void)showError:(NSString *)msg
{
  [_screen removeFromSuperview];
  _screen = nil;
  [_errorLabel setStringValue: msg];
  [_errorLabel setFrame: NSInsetRect([_content bounds], 16, 16)];
  [_content addSubview: _errorLabel];
  [_window setTitle: [NSString stringWithFormat: @"%@ — error", [_path lastPathComponent]]];
}

- (void)reload:(id)sender
{
  _mtime = TPModDate(_path);
  _sampleMtime = TPModDate([self samplePath]);
  NSError *err = nil;
  TRMarkupDocument *doc = [TRMarkupDocument documentWithContentsOfFile: _path error: &err];
  TRBoxView *screen = doc ? [TRLoader loadDocument: doc owner: nil error: &err] : nil;
  if (screen && [[NSFileManager defaultManager] fileExistsAtPath: [self samplePath]])
    {
      NSData *d = [NSData dataWithContentsOfFile: [self samplePath]];
      NSDictionary *sample = d ? [NSJSONSerialization JSONObjectWithData: d options: 0 error: &err] : nil;
      if (![sample isKindOfClass: [NSDictionary class]] || ![TRLoader applySample: sample toView: screen error: &err])
        screen = nil;
    }
  if (screen == nil)
    {
      [self showError: err ? [err localizedDescription] : @"cannot load"];
      return;
    }
  [_errorLabel removeFromSuperview];
  [_screen removeFromSuperview];
  _screen = screen;
  [_screen setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [_screen setFrame: [_content bounds]];
  [_content addSubview: _screen positioned: NSWindowBelow relativeTo: nil];
  [_overlay removeFromSuperview];
  if (_inspector) [_content addSubview: _overlay];
  [self relayoutAndLint];
}

/* After any layout: refresh lint findings, title and overlay. */
- (void)relayoutAndLint
{
  if (_screen == nil) return;
  [_screen layoutTrellis];
  NSSize s = [_content bounds].size;
  _findings = [self lintScreen];
  NSUInteger errors = 0;
  for (NSDictionary *f in _findings) if ([f[@"severity"] isEqualToString: @"error"]) errors++;
  [_window setTitle: [NSString stringWithFormat: @"%@ — %g × %g — %lu lint (%lu errors)",
                       [_path lastPathComponent], s.width, s.height,
                       (unsigned long)[_findings count], (unsigned long)errors]];
  _overlay.target = _screen;
  _overlay.findings = _findings;
  [_overlay setFrame: [_content bounds]];
  [_overlay setNeedsDisplay: YES];
}

static NSDictionary *TPDump(NSView *v, TRNode *node)
{
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  NSRect f = [v frame];
  d[@"class"] = NSStringFromClass([v class]);
  if ([[v identifier] length]) d[@"id"] = [v identifier];
  d[@"x"] = @(f.origin.x); d[@"y"] = @(f.origin.y);
  d[@"width"] = @(f.size.width); d[@"height"] = @(f.size.height);
  if ([v isHidden]) d[@"hidden"] = @YES;
  if (node.style.position == TRPositionAbsolute) d[@"position"] = @"absolute";
  if ([v isKindOfClass: [NSControl class]] && [(NSControl *)v cell])
    {
      NSCell *cell = [(NSControl *)v cell];
      NSSize ic = TRCellSize(cell);
      d[@"intrinsic"] = @{@"width": @(ceil(ic.width)), @"height": @(ceil(ic.height))};
      if ([cell type] == NSTextCellType && ![v isKindOfClass: [NSButton class]]
          && ![v isKindOfClass: [NSPopUpButton class]] && [[cell stringValue] length])
        {
          NSSize need;
          TRViewIsClipped(v, &need);
          d[@"text"] = [cell stringValue];
          d[@"needed"] = @{@"width": @(ceil(need.width)), @"height": @(ceil(need.height))};
        }
    }
  NSMutableArray *kids = [NSMutableArray array];
  if ([v isKindOfClass: [TRScrollBox class]])
    {
      TRBoxView *cb = [(TRScrollBox *)v contentBox];
      d[@"overflow"] = @"scroll";
      [kids addObject: TPDump(cb, cb.node)];
    }
  else if ([v isKindOfClass: [TRBoxView class]])
    for (TRNode *c in [(TRBoxView *)v node].children)
      if (c.context) [kids addObject: TPDump(c.context, c)];
  if ([kids count]) d[@"children"] = kids;
  return d;
}

- (NSArray *)lintScreen
{
  NSSize s = [_content bounds].size;
  return TRLintFrameTree(TPDump(_screen, _screen.node), s.width, s.height);
}

- (void)windowDidResize:(NSNotification *)n
{
  [self relayoutAndLint];
}

- (void)toggleInspector:(id)sender
{
  _inspector = !_inspector;
  [_overlay removeFromSuperview];
  if (_inspector) [_content addSubview: _overlay];
  [self relayoutAndLint];
}

- (void)setWidthPreset:(id)sender
{
  NSRect f = [_window frame];
  NSRect c = [_window contentRectForFrameRect: f];
  c.size.width = [sender tag];
  [_window setFrame: [_window frameRectForContentRect: c] display: YES];
}

- (void)chooseTheme:(id)sender
{
  NSString *name = [sender representedObject];
#ifdef GNUSTEP
  GSTheme *t = [GSTheme loadThemeNamed: [name isEqualToString: @"GNUstep"] ? nil : name];
  if (t) [GSTheme setTheme: t];
#else
  if (@available(macOS 10.14, *))
    [NSApp setAppearance: [NSAppearance appearanceNamed:
      [name isEqualToString: @"Dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
#endif
  [self reload: nil];   /* controls re-measure under the new theme */
}

- (void)snapshotTo:(NSString *)path
{
  [self relayoutAndLint];
  NSRect b = [_content bounds];
  [_content display];
  NSBitmapImageRep *rep = [_content bitmapImageRepForCachingDisplayInRect: b];
  [_content cacheDisplayInRect: b toBitmapImageRep: rep];
  [[rep representationUsingType: NSPNGFileType properties: @{}] writeToFile: path atomically: YES];
  printf("%s\n", [[_window title] UTF8String]);
}

@end

int main(int argc, const char **argv)
{
  @autoreleasepool
    {
      NSString *path = nil, *snapshot = nil;
      NSSize size = NSMakeSize(640, 480);
      BOOL inspector = NO;
      for (int i = 1; i < argc; i++)
        {
          NSString *a = [NSString stringWithUTF8String: argv[i]];
          NSString *next = i + 1 < argc ? [NSString stringWithUTF8String: argv[i + 1]] : nil;
          if ([a isEqualToString: @"--snapshot"] && next) { snapshot = next; i++; }
          else if ([a isEqualToString: @"--width"] && next) { size.width = [next doubleValue]; i++; }
          else if ([a isEqualToString: @"--height"] && next) { size.height = [next doubleValue]; i++; }
          else if ([a isEqualToString: @"--inspector"]) inspector = YES;
          else if ([[a pathExtension] isEqualToString: @"trellis"]) path = [a stringByStandardizingPath];
          else if ([a hasPrefix: @"-"] && next && ![next hasPrefix: @"-"]) i++;   /* NSUserDefaults args, e.g. -GSTheme X */
        }
      [NSApplication sharedApplication];
      TPController *c = [[TPController alloc] initWithPath: path snapshot: snapshot size: size inspector: inspector];
      if (snapshot)
        {
          /* Headless check: no run loop, no services (pasteboard etc.). */
          [c applicationDidFinishLaunching: nil];
          return 0;
        }
      [NSApp setDelegate: c];
      [NSApp run];
    }
  return 0;
}
