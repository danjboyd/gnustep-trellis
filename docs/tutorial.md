# Build your first Trellis app

In about fifteen minutes you'll build **Greeter**, a small GNUstep app whose
window is laid out by Trellis: a title, a name field with a button, and a
greeting that wraps. You'll check the layout without running the app,
render it at two widths, make it responsive, and add a smoke test.

CI follows this page literally: `scripts/check-tutorial.sh` extracts every
file and every `sh` step below and runs them, so what you read here builds.

## 1. Trellis, built and installed

You need the GNUstep toolchain with clang and libobjc2
([building.md](building.md) builds one into `~/opt/trellis-toolchain`).
In your Trellis checkout:

```sh step
cd "$TRELLIS_SRC"
. scripts/env.sh
make
make install
cd -
```

`make install` puts the libraries, the headers (`<Trellis/...>`) and the
tools (`trellis-lint`, `trellis-render`) into your GNUstep Local domain,
which `scripts/env.sh` already has on your paths.

## 2. The project

Make a directory with four files:

```sh step
mkdir -p Greeter
cd Greeter
```

**The layout,** `Greeter.trellis`. Elements build views, `id` names an
outlet on the owner, `action` names a method, and the `<style>` block is
CSS: flexbox, gaps, and the built-in `--tr-*` tokens, whose sizes follow
the running theme.

```xml file=Greeter/Greeter.trellis
<!-- owner: GreeterController -->
<column id="root" class="window">
  <label class="title" no-outlet="yes">Say hello</label>
  <row class="entry">
    <field id="nameField" class="name" placeholder="Your name"/>
    <button id="greetButton" action="greet:" default="yes">Greet</button>
  </row>
  <text id="greeting" class="greeting">Type a name and press <b>Greet</b>.</text>
</column>
<style>
  .window   { padding: var(--tr-space-l); gap: var(--tr-space-m); }
  .title    { font-size: var(--tr-title-font-size); font-weight: bold; }
  .entry    { gap: var(--tr-space-s); }
  .name     { flex: 1; }
  .greeting { color: var(--tr-muted); }
</style>
```

**The owner,** `GreeterController.h` and `.m`. Each `id` in the layout
is a property here, and `greet:` is the button's action.

```objc file=Greeter/GreeterController.h
#import <AppKit/AppKit.h>

@interface GreeterController : NSObject
@property (nonatomic, strong) NSView *root;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSButton *greetButton;
@property (nonatomic, strong) NSTextField *greeting;
- (IBAction)greet:(id)sender;
@end
```

```objc file=Greeter/GreeterController.m
#import "GreeterController.h"

@implementation GreeterController
- (IBAction)greet:(id)sender
{
  NSString *name = [[self.nameField stringValue]
    stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
  [self.greeting setStringValue: [NSString stringWithFormat: @"Hello, %@!",
                                  [name length] ? name : @"world"]];
}
@end
```

**The app,** `main.m`. It loads the layout with the controller as owner
and makes the result the window's content view. Trellis lays it out
again whenever the window resizes, and links the controls into the Tab
order. (The smoke test is step 6.)

```objc file=Greeter/main.m
#import <AppKit/AppKit.h>
#import <Trellis/TRLoader.h>
#import "GreeterController.h"

@interface AppDelegate : NSObject
{
  NSWindow *_window;
  GreeterController *_controller;
}
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  _controller = [GreeterController new];
  NSString *path = [[NSBundle mainBundle] pathForResource: @"Greeter" ofType: @"trellis"];
  NSError *err = nil;
  TRBoxView *box = [TRLoader loadFile: path owner: _controller error: &err];
  if (box == nil)
    {
      NSLog(@"%@", [err localizedDescription]);
      exit(1);
    }
  _window = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 420, 170)
                                        styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                   | NSWindowStyleMaskResizable
                                          backing: NSBackingStoreBuffered defer: NO];
  [_window setTitle: @"Greeter"];
  [_window setContentView: box];
  [_window setInitialFirstResponder: box.firstKeyView];
  [_window makeKeyAndOrderFront: nil];
  if (getenv("GREETER_SMOKE")) [self smokeTest];
}

/* Step 6: type a name, press the button, check the greeting. */
- (void)smokeTest
{
  [_controller.nameField setStringValue: @"Ada"];
  [_controller.greetButton performClick: nil];
  BOOL ok = [[_controller.greeting stringValue] isEqualToString: @"Hello, Ada!"];
  printf("%s\n", ok ? "GREETER OK" : "GREETER FAIL");
  exit(ok ? 0 : 1);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}
@end

int main(int argc, const char **argv)
{
  @autoreleasepool
    {
      NSApplication *app = [NSApplication sharedApplication];
      AppDelegate *delegate = [AppDelegate new];
      [app setDelegate: (id)delegate];
      [app run];
    }
  return 0;
}
```

**The makefile,** `GNUmakefile`: a GNUstep app with ARC, linked against
both Trellis libraries, with the layout as a resource.

```make file=Greeter/GNUmakefile
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Greeter
Greeter_OBJC_FILES = main.m GreeterController.m
Greeter_RESOURCE_FILES = Greeter.trellis
Greeter_GUI_LIBS = -lTrellis -lTrellisEngine
ADDITIONAL_OBJCFLAGS = -fobjc-arc -fblocks

include $(GNUSTEP_MAKEFILES)/application.make
```

## 3. Check the layout before you build

`trellis-lint` reads the layout and the owner's header. It reports
unknown elements and properties, bad values, ids with no outlet, actions
the owner doesn't declare, and colours that break in dark mode.

```sh step
trellis-lint Greeter.trellis --owner GreeterController.h
```

It should say `0 error(s), 0 warning(s)`. Try a typo, such as
`action="greeet:"`, and run it again: lint names the line, and the
missing method.

## 4. See it at two widths

`trellis-render` lays the file out at each width and writes a PNG (and
with `--lint`, checks for clipped text and overflow). There's no app to
run yet:

```sh step
trellis-render Greeter.trellis --widths 320,560 --height 170 --png greeter.png --lint
```

That writes `greeter-320.png` and `greeter-560.png`. (On a machine with
no display, put `scripts/run-headless.sh` from the Trellis checkout in
front of the command.) For live editing, open the file in TrellisPreview
instead: it re-renders on every save.

## 5. Make it responsive

At 320 px the field gets squeezed beside the button. A container query
fixes that: below 360 px, the row becomes a column. Add
`container-type` to the root, so queries can test its width, and the
query itself, at the end of the `<style>` block:

```sh step
sed -i 's|  .window   { padding|  .window   { container-type: inline-size; padding|' Greeter.trellis
sed -i 's|</style>|  @container (max-width: 359px) { .entry { flex-direction: column; align-items: stretch; } }\n</style>|' Greeter.trellis
trellis-lint Greeter.trellis --owner GreeterController.h
trellis-render Greeter.trellis --widths 320,560 --height 200 --png greeter.png --lint
```

Now `greeter-320.png` shows the button under the field, and
`greeter-560.png` is unchanged.

## 6. Build, run, and test

```sh step
make
```

Run it with `openapp ./Greeter.app`, type a name, and press Return:
Greet is the default button. Resize the window below 360 px and the row
folds.

`main.m` has a smoke test: with `GREETER_SMOKE` set, it types a name,
clicks Greet, checks the greeting, and exits.

```sh step
GREETER_SMOKE=1 ./Greeter.app/Greeter
```

It prints `GREETER OK`. Run it in your CI the same way, under
`scripts/run-headless.sh` or another X server.

## Where next

- [agents.md](agents.md): every element, property and pattern, including
  grids, templates, `<virtual>` lists of thousands of rows, rich text,
  and layout transitions.
- `Examples/TrellisDemo`: three screens with sample data (`*.sample.json`
  fills them for `trellis-render`).
- **Hot reload:** run your app with `TRELLIS_HOT_RELOAD=1` and edit
  `Greeter.app/Resources/Greeter.trellis` (the copy the app loads): the
  window updates when you save.
