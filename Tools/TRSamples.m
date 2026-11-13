/* TRSamples.m - built-in sample screens for trellis-render, written with
   the typed + inline-style API (until .trellis files land).

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import "TRBoxView.h"

static NSTextField *TRLabel(NSString *text, NSString *ident)
{
  NSTextField *f = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
  [f setStringValue: text];
  [f setEditable: NO];
  [f setSelectable: NO];
  [f setBezeled: NO];
  [f setDrawsBackground: NO];
  [f setIdentifier: ident];
  return f;
}

static NSTextField *TRWrappingLabel(NSString *text, NSString *ident)
{
  NSTextField *f = TRLabel(text, ident);
  [[f cell] setWraps: YES];
  [[f cell] setLineBreakMode: NSLineBreakByWordWrapping];
  return f;
}

static NSTextField *TRField(NSString *placeholder, NSString *ident)
{
  NSTextField *f = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
  [f setStringValue: @""];
  [[f cell] setPlaceholderString: placeholder];
  [f setIdentifier: ident];
  return f;
}

static NSButton *TRButton(NSString *title, NSString *ident)
{
  NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
  [b setTitle: title];
  [b setBezelStyle: NSRoundedBezelStyle];
  if (ident) [b setIdentifier: ident];
  return b;
}

static NSButton *TRCheckbox(NSString *title, NSString *ident)
{
  NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
  [b setButtonType: NSSwitchButton];
  [b setTitle: title];
  [b setIdentifier: ident];
  return b;
}

static NSPopUpButton *TRPopup(NSArray *items, NSString *ident)
{
  NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 10, 10) pullsDown: NO];
  [p addItemsWithTitles: items];
  [p setIdentifier: ident];
  return p;
}

/* (a) An AIManager-style ask detail. */
static TRBoxView *TRSampleAsk(void)
{
  TRBoxView *ask = [TRBoxView boxWithStyle:
    @"container-type: inline-size; flex-direction: column; padding: 16px; gap: 12px; background-color: #fafafa"];
  [ask setIdentifier: @"ask"];

  TRBoxView *header = [TRBoxView boxWithStyle: @"flex-direction: row; gap: 8px; align-items: baseline"];
  [header setIdentifier: @"header"];
  [header addSubview: TRLabel(@"approve", @"kind")
               style: @"flex: none; padding: 2px 6px; color: #1c71d8; font-weight: bold"];
  [header addSubview: TRWrappingLabel(@"Tag example-cli v0.1.8 as rc2 and publish the release notes?", @"title")
               style: @"flex: 1; font-size: 15px"];
  [header addSubview: TRLabel(@"12 min ago", @"age") style: @"flex: none; color: #777"];
  [ask addSubview: header];

  [ask addSubview: TRWrappingLabel(
    @"All tests pass on Linux and Windows. The macOS job is still flaky on the "
    @"notarization step; I re-ran it twice and it passed the second time. This "
    @"blocks the rc2 tag and the packager update that depends on it.", @"body")
            style: @"flex: 1 1 auto; min-height: 60px"];

  TRBoxView *opts = [TRBoxView boxWithStyle: @"flex-direction: column; gap: 6px"];
  [opts setIdentifier: @"options"];
  [ask addSubview: opts];
  /* flex-basis applies to the main axis: 160px wide in a row, but it would
     be 160px *tall* in the narrow column, so it is only set when wide. */
  for (NSString *t in @[@"Approve: tag rc2", @"Re-run the macOS job first", @"Defer to Monday"])
    {
      NSButton *b = TRButton(t, nil);
      [opts addSubview: b];
      [opts addConditionalStyle: @"flex: 1 1 160px" when: @"width >= 560px" forSubview: b];
    }
  [opts addConditionalStyle: @"flex-direction: row; flex-wrap: wrap" when: @"width >= 560px"];
  return ask;
}

/* (b) A settings form: labels above controls when narrow, a label column
   when wide. */
static TRBoxView *TRSampleSettings(void)
{
  TRBoxView *form = [TRBoxView boxWithStyle:
    @"container-type: inline-size; flex-direction: column; gap: 10px; padding: 20px"];
  [form setIdentifier: @"settings"];
  NSArray *rows = @[
    @[ TRLabel(@"Display name", @"nameLabel"), TRField(@"the maintainer", @"name") ],
    @[ TRLabel(@"Theme", @"themeLabel"), TRPopup(@[@"Adwaita", @"Gumdrop", @"GNUstep"], @"theme") ],
    @[ TRLabel(@"Density", @"densityLabel"), TRPopup(@[@"Comfortable", @"Compact"], @"density") ],
    @[ TRLabel(@"Updates", @"updatesLabel"), TRCheckbox(@"Check for updates automatically", @"updates") ],
  ];
  for (NSArray *pair in rows)
    {
      TRBoxView *r = [TRBoxView boxWithStyle: @"flex-direction: column; gap: 4px"];
      [r addSubview: pair[0] style: @"flex: none"];
      [r addSubview: pair[1] style: @"flex: 1; max-width: 360px"];
      [form addSubview: r];
      [r addConditionalStyle: @"flex-direction: row; align-items: baseline; gap: 12px" when: @"width >= 480px"];
      [r addConditionalStyle: @"flex: 0 0 120px; text-align: right" when: @"width >= 480px"
                  forSubview: pair[0]];
    }
  TRBoxView *buttons = [TRBoxView boxWithStyle: @"flex-direction: row; justify-content: flex-end; gap: 8px; margin-top: 8px"];
  [buttons addSubview: TRButton(@"Cancel", @"cancel")];
  [buttons addSubview: TRButton(@"Save", @"save")];
  [form addSubview: buttons];
  return form;
}

/* (c) A toolbar row. */
static TRBoxView *TRSampleToolbar(void)
{
  TRBoxView *bar = [TRBoxView boxWithStyle:
    @"container-type: inline-size; flex-direction: row; align-items: center; gap: 6px; padding: 4px 8px; background-color: #ebebeb"];
  [bar setIdentifier: @"toolbar"];
  [bar addSubview: TRButton(@"<", @"back")];
  [bar addSubview: TRButton(@">", @"forward")];
  [bar addSubview: TRField(@"Search", @"search") style: @"flex: 1 1 200px; min-width: 120px; max-width: 480px"];
  NSView *spacer = [[NSView alloc] initWithFrame: NSZeroRect];
  [bar addSubview: spacer style: @"flex: 1"];
  NSButton *share = TRButton(@"Share", @"share");
  [bar addSubview: share];
  [bar addSubview: TRButton(@"Menu", @"menu")];
  [bar addConditionalStyle: @"display: none" when: @"width < 500px" forSubview: share];
  return bar;
}

TRBoxView *TRSampleScreen(NSString *name)
{
  if ([name isEqualToString: @"ask"]) return TRSampleAsk();
  if ([name isEqualToString: @"settings"]) return TRSampleSettings();
  if ([name isEqualToString: @"toolbar"]) return TRSampleToolbar();
  return nil;
}

NSArray<NSString *> *TRSampleScreenNames(void)
{
  return @[@"ask", @"settings", @"toolbar"];
}
