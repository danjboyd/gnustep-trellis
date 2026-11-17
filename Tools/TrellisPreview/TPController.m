/* TPController.m - Trellis Preview: open a .trellis file, watch it, show it.

   - Live reload: the file (and Name.sample.json) are polled twice a second.
   - Resize the window to see the layout respond; View > Width presets.
   - View > Inspector draws box outlines and lint findings over the screen.
   - View > Focus Order numbers the controls in Tab order and links them
     (--focus-order for a snapshot). The frames JSON lists the order too.
   - Theme menu (GNUstep: any installed GSTheme; macOS: light/dark).
   - View > Light / Dark Appearance (GNUstep: the Adwaita colour scheme,
     set for this process only, by relaunching; macOS: the window's
     appearance, in place).
   - File > Export PNG… and Export Frames JSON… (the JSON trellis-render
     --json writes, with lint). Headless: --snapshot out.png
     [--export-json out.json] [--appearance light|dark].
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
#import "TRVirtualBox.h"
#import "TRSplitView.h"
#import "TRViewMeasure.h"
#import "TRLint.h"
#ifdef GNUSTEP
#import <GNUstepGUI/GSTheme.h>
#endif

/* ---- Overlay ---- */

/* The views in the root's key-view loop that can take focus now, in Tab
   order (disabled ones are skipped, as Tab skips them). */
static NSArray<NSView *> *TPFocusOrder(TRBoxView *root)
{
  NSMutableArray *a = [NSMutableArray array];
  NSView *first = root.firstKeyView, *v = first;
  for (int i = 0; v != nil && i < 512; i++)
    {
      /* On GNUstep the chain wraps through a sentinel outside the tree. */
      if ([v isDescendantOf: root] && ![a containsObject: v] && [v canBecomeKeyView]) [a addObject: v];
      v = [v nextKeyView];
      if (v == first) break;
    }
  return a;
}

@interface TPOverlay : NSView
@property (nonatomic, weak) NSView *target;
@property (nonatomic) BOOL showOutlines;          /* View > Inspector */
@property (nonatomic) BOOL showFocusOrder;        /* View > Focus Order */
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
      else if ([v isKindOfClass: [TRVirtualBox class]]) kids = [(TRVirtualBox *)v visibleItemViews];
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
  if (self.showFocusOrder && [t isKindOfClass: [TRBoxView class]])
    {
      NSArray *order = TPFocusOrder((TRBoxView *)t);
      NSColor *ink = [NSColor colorWithCalibratedRed: 0.55 green: 0.2 blue: 0.75 alpha: 0.9];
      NSBezierPath *link = [NSBezierPath bezierPath];
      [link setLineWidth: 1.5];
      CGFloat dash[] = { 4, 3 };
      [link setLineDash: dash count: 2 phase: 0];
      for (NSUInteger i = 0; i < [order count]; i++)
        {
          NSRect r = [self convertRect: [order[i] bounds] fromView: order[i]];
          NSPoint c = NSMakePoint(NSMidX(r), NSMidY(r));
          if (i == 0) [link moveToPoint: c]; else [link lineToPoint: c];
        }
      [[ink colorWithAlphaComponent: 0.45] set];
      [link stroke];
      NSDictionary *num = @{NSFontAttributeName: [NSFont boldSystemFontOfSize: 10],
                            NSForegroundColorAttributeName: [NSColor whiteColor]};
      for (NSUInteger i = 0; i < [order count]; i++)
        {
          NSRect r = [self convertRect: [order[i] bounds] fromView: order[i]];
          [ink set];
          NSFrameRectWithWidth(r, 1.5);
          NSString *label = [NSString stringWithFormat: @"%lu", (unsigned long)i + 1];
          NSSize ts = [label sizeWithAttributes: num];
          CGFloat d = MAX(ts.width + 6, ts.height + 2);
          NSRect badge = NSMakeRect(NSMinX(r) - d / 2, NSMinY(r) - d / 2, d, d);
          [[NSBezierPath bezierPathWithOvalInRect: badge] fill];
          [label drawAtPoint: NSMakePoint(NSMidX(badge) - ts.width / 2, NSMidY(badge) - ts.height / 2)
              withAttributes: num];
        }
    }
  if (!self.showOutlines) return;
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
  BOOL _focusOrder;
  NSString *_snapshot;
  NSSize _initialSize;
  NSArray *_findings;
  NSString *_appearance;   /* nil (theme default), "light" or "dark" */
  NSString *_exportJSON;   /* headless: write the frames JSON here */
}
@end

@implementation TPController

- (void)setExportJSON:(NSString *)path { _exportJSON = [path copy]; }
- (void)setShowsFocusOrder:(BOOL)yn { _focusOrder = yn; }

/* The overlay is up while it has something to draw. */
- (void)updateOverlay
{
  [_overlay removeFromSuperview];
  _overlay.showOutlines = _inspector;
  _overlay.showFocusOrder = _focusOrder;
  if (_inspector || _focusOrder) [_content addSubview: _overlay];
}
- (void)setInitialAppearance:(NSString *)a { _appearance = [a copy]; }

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
  [file addItemWithTitle: @"Export PNG…" action: @selector(exportPNG:) keyEquivalent: @"e"];
  [file addItemWithTitle: @"Export Frames JSON…" action: @selector(exportJSON:) keyEquivalent: @"E"];
  [file addItemWithTitle: @"Quit" action: @selector(terminate:) keyEquivalent: @"q"];
  [[main addItemWithTitle: @"File" action: NULL keyEquivalent: @""] setSubmenu: file];

  NSMenu *view = [[NSMenu alloc] initWithTitle: @"View"];
  [view addItemWithTitle: @"Inspector" action: @selector(toggleInspector:) keyEquivalent: @"i"];
  [view addItemWithTitle: @"Focus Order" action: @selector(toggleFocusOrder:) keyEquivalent: @"k"];
  for (NSNumber *w in @[@360, @520, @800, @1200])
    {
      NSMenuItem *it = (NSMenuItem *)[view addItemWithTitle: [NSString stringWithFormat: @"Width %@", w]
                                       action: @selector(setWidthPreset:) keyEquivalent: @""];
      [it setTag: [w integerValue]];
    }
  [view addItem: [NSMenuItem separatorItem]];
  [[view addItemWithTitle: @"Light Appearance" action: @selector(chooseAppearance:) keyEquivalent: @""]
    setRepresentedObject: @"light"];
  [[view addItemWithTitle: @"Dark Appearance" action: @selector(chooseAppearance:) keyEquivalent: @"d"]
    setRepresentedObject: @"dark"];
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

  if (_appearance) [self applyAppearance: _appearance];
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
  [self updateOverlay];
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

/* Controls a pointer or finger acts on (for the touch-target lint). */
static BOOL TRIsInteractive(NSView *v)
{
  if ([v isHidden]) return NO;
  if ([v isKindOfClass: [NSTextField class]]) return [(NSTextField *)v isEditable];
  if ([v isKindOfClass: [NSButton class]] || [v isKindOfClass: [NSSlider class]]
      || [v isKindOfClass: [NSStepper class]] || [v isKindOfClass: [NSSegmentedControl class]]
      || [v isKindOfClass: [NSColorWell class]])
    return [(NSControl *)v isEnabled];
  return NO;
}

static NSDictionary *TPDump(NSView *v, TRNode *node)
{
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  NSRect f = [v frame];
  d[@"class"] = NSStringFromClass([v class]);
  if (TRIsInteractive(v)) d[@"interactive"] = @YES;
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
  else if ([v isKindOfClass: [TRSplitView class]])
    for (NSView *pv in [(TRSplitView *)v panes])
      [kids addObject: TPDump(pv, [pv isKindOfClass: [TRBoxView class]] ? ((TRBoxView *)pv).node : nil)];
  else if ([v isKindOfClass: [TRVirtualBox class]])
    {
      TRVirtualBox *vb = (TRVirtualBox *)v;
      CGFloat top = [[vb contentView] bounds].origin.y;
      d[@"overflow"] = @"scroll";
      for (NSView *iv in [vb visibleItemViews])
        {
          NSMutableDictionary *k = [TPDump(iv, [iv isKindOfClass: [TRBoxView class]] ? ((TRBoxView *)iv).node : nil) mutableCopy];
          k[@"y"] = @([iv frame].origin.y - top);
          [kids addObject: k];
        }
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
  [self updateOverlay];
  [self relayoutAndLint];
}

- (void)toggleFocusOrder:(id)sender
{
  _focusOrder = !_focusOrder;
  [self updateOverlay];
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

/* Light or dark. GNUstep has no appearance API: the Adwaita theme reads
   its colour scheme from a default when it loads, and activating a theme
   twice in one process isn't safe (Adwaita's method swizzling recurses).
   So the scheme is set in the volatile argument domain before the theme
   loads (main, for --appearance; nothing is written to the user's
   defaults), and switching later relaunches Preview with the same file,
   size and theme. Cocoa sets the window's appearance in place. */
static void TPSetSchemeDefault(NSString *appearance)
{
#ifdef GNUSTEP
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *args = [[defs volatileDomainForName: NSArgumentDomain] mutableCopy]
    ?: [NSMutableDictionary dictionary];
  args[@"GnomeThemeColorScheme"] = [appearance isEqualToString: @"dark"] ? @"force-dark" : @"force-light";
  [defs removeVolatileDomainForName: NSArgumentDomain];
  [defs setVolatileDomain: args forName: NSArgumentDomain];
#else
  (void)appearance;
#endif
}

- (void)applyAppearance:(NSString *)appearance
{
  _appearance = [appearance copy];
#ifndef GNUSTEP
  if (@available(macOS 10.14, *))
    {
      NSAppearance *ap = appearance ? [NSAppearance appearanceNamed:
        [appearance isEqualToString: @"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua] : nil;
      [_window setAppearance: ap];
      /* Also on the content view: a snapshot never shows the window, and
         views draw under the appearance they have, not the window's. */
      [_content setAppearance: ap];
    }
#endif
}

#ifndef GNUSTEP
/* Run a block with the content's appearance as the drawing appearance, so
   dynamic colours (window background, label colours) resolve under it. */
- (void)underContentAppearance:(void (^)(void))block
{
  if (@available(macOS 11.0, *))
    [[_content effectiveAppearance] performAsCurrentDrawingAppearance: block];
  else
    block();
}
#endif

#ifdef GNUSTEP
- (void)relaunchWithAppearance:(NSString *)appearance
{
  NSSize s = [_content bounds].size;
  NSMutableArray *args = [NSMutableArray array];
  if (_path) [args addObject: _path];
  [args addObjectsFromArray: @[@"--appearance", appearance,
                               @"--width", [NSString stringWithFormat: @"%.0f", s.width],
                               @"--height", [NSString stringWithFormat: @"%.0f", s.height]]];
  if (_inspector) [args addObject: @"--inspector"];
  if (_focusOrder) [args addObject: @"--focus-order"];
  NSString *theme = [[GSTheme theme] name];
  if ([theme length]) [args addObjectsFromArray: @[@"-GSTheme", theme]];
  NSTask *t = [NSTask new];
  [t setLaunchPath: [[NSBundle mainBundle] executablePath]];
  [t setArguments: args];
  @try { [t launch]; }
  @catch (NSException *e) { [self showError: [NSString stringWithFormat: @"Could not relaunch: %@", [e reason]]]; return; }
  [NSApp terminate: nil];
}
#endif

- (void)chooseAppearance:(id)sender
{
  NSString *a = [sender representedObject];
  if ([a isEqualToString: _appearance]) return;
#ifdef GNUSTEP
  [self relaunchWithAppearance: a];
#else
  [self applyAppearance: a];
  [self reload: nil];   /* controls re-measure under the new colours */
#endif
}

- (NSData *)pngData
{
  [self relayoutAndLint];
  NSRect b = [_content bounds];
  [_content display];
  NSBitmapImageRep *rep = [_content bitmapImageRepForCachingDisplayInRect: b];
#ifdef GNUSTEP
  [_content cacheDisplayInRect: b toBitmapImageRep: rep];
#else
  [self underContentAppearance: ^{
    [_content cacheDisplayInRect: b toBitmapImageRep: rep];
    /* The window background, under what the views drew, as on screen. */
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep: rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: ctx];
    [[NSColor windowBackgroundColor] set];
    NSRectFillUsingOperation(b, NSCompositingOperationDestinationOver);
    [NSGraphicsContext restoreGraphicsState];
  }];
#endif
  return [rep representationUsingType: NSPNGFileType properties: @{}];
}

static NSString *TPThemeName(void)
{
#ifdef GNUSTEP
  NSString *n = [[GSTheme theme] name];
  return [n length] ? n : @"default";
#else
  return @"default";
#endif
}

/* The same document trellis-render --json writes. */
- (NSData *)framesJSON
{
  if (_screen == nil) return nil;
  [self relayoutAndLint];
  NSSize s = [_content bounds].size;
  NSMutableDictionary *tree = [TPDump(_screen, _screen.node) mutableCopy];
#ifdef GNUSTEP
  NSColor *wb = [[NSColor windowBackgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
#else
  __block NSColor *wb = nil;
  [self underContentAppearance: ^{ wb = [[NSColor windowBackgroundColor] colorUsingColorSpace: [NSColorSpace sRGBColorSpace]]; }];
#endif
  if (wb)
    tree[@"windowBackground"] = [NSString stringWithFormat: @"#%02x%02x%02x", (int)lround([wb redComponent] * 255),
                                  (int)lround([wb greenComponent] * 255), (int)lround([wb blueComponent] * 255)];
  /* Tab order: each control's id, else its class. */
  NSMutableArray *focus = [NSMutableArray array];
  for (NSView *v in TPFocusOrder(_screen)) [focus addObject: [v identifier] ?: NSStringFromClass([v class])];
  NSDictionary *doc = @{
    @"trellis": @"0.1", @"source": _path ?: @"",
    @"theme": TPThemeName(),
    @"appearance": _appearance ?: @"default",
    @"viewport": @{@"width": @(s.width), @"height": @(s.height), @"scale": @1},
    @"root": tree, @"lint": TRLintFrameTree(tree, s.width, s.height),
    @"focusOrder": focus };
  return [NSJSONSerialization dataWithJSONObject: doc options: NSJSONWritingPrettyPrinted error: NULL];
}

- (void)exportWithType:(NSString *)ext
{
  NSSavePanel *panel = [NSSavePanel savePanel];
  NSString *base = [[[_path lastPathComponent] stringByDeletingPathExtension] ?: @"screen"
    stringByAppendingFormat: @"-%.0f", [_content bounds].size.width];
  [panel setNameFieldStringValue: [base stringByAppendingPathExtension: ext]];
  if ([panel runModal] != NSModalResponseOK) return;
  NSData *d = [ext isEqualToString: @"png"] ? [self pngData] : [self framesJSON];
  if (![d writeToURL: [panel URL] atomically: YES])
    [self showError: [NSString stringWithFormat: @"Could not write %@", [[panel URL] path]]];
}

- (void)exportPNG:(id)sender { [self exportWithType: @"png"]; }
- (void)exportJSON:(id)sender { [self exportWithType: @"json"]; }

- (void)snapshotTo:(NSString *)path
{
  [[self pngData] writeToFile: path atomically: YES];
  if (_exportJSON) [[self framesJSON] writeToFile: _exportJSON atomically: YES];
  printf("%s\n", [[_window title] UTF8String]);
}

@end

int main(int argc, const char **argv)
{
  @autoreleasepool
    {
      NSString *path = nil, *snapshot = nil;
      NSSize size = NSMakeSize(640, 480);
      BOOL inspector = NO, focusOrder = NO;
      NSString *exportJSON = nil, *appearance = nil;
      for (int i = 1; i < argc; i++)
        {
          NSString *a = [NSString stringWithUTF8String: argv[i]];
          NSString *next = i + 1 < argc ? [NSString stringWithUTF8String: argv[i + 1]] : nil;
          if ([a isEqualToString: @"--snapshot"] && next) { snapshot = next; i++; }
          else if ([a isEqualToString: @"--width"] && next) { size.width = [next doubleValue]; i++; }
          else if ([a isEqualToString: @"--height"] && next) { size.height = [next doubleValue]; i++; }
          else if ([a isEqualToString: @"--inspector"]) inspector = YES;
          else if ([a isEqualToString: @"--focus-order"]) focusOrder = YES;
          else if ([a isEqualToString: @"--export-json"] && next) { exportJSON = next; i++; }
          else if ([a isEqualToString: @"--appearance"] && next) { appearance = next; i++; }
          else if ([[a pathExtension] isEqualToString: @"trellis"]) path = [a stringByStandardizingPath];
          else if ([a hasPrefix: @"-"] && next && ![next hasPrefix: @"-"]) i++;   /* NSUserDefaults args, e.g. -GSTheme X */
        }
      if (appearance) TPSetSchemeDefault(appearance);   /* before the theme loads */
      [NSApplication sharedApplication];
      TPController *c = [[TPController alloc] initWithPath: path snapshot: snapshot size: size inspector: inspector];
      [c setExportJSON: exportJSON];
      [c setShowsFocusOrder: focusOrder];
      if (appearance) [c setInitialAppearance: appearance];
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
