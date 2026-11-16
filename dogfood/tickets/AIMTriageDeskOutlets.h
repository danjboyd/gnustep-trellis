/* The owner contract for dogfood/tickets/*.trellis: the outlets and actions
   AIManager's AIMTriageDeskView would expose if its -layout were replaced by
   a Trellis spec. A stand-in for review only. It is not AIManager's header,
   and nothing here touches the AIManager repo. */
#import <AppKit/AppKit.h>

@interface AIMTriageDeskView : NSView
@property (nonatomic, strong) NSView *desk;
@property (nonatomic, strong) NSButton *railToggle;     /* narrow widths: opens the rail */
@property (nonatomic, strong) NSView *pulse;
@property (nonatomic, strong) NSTextField *filter;
@property (nonatomic, strong) NSView *rail;             /* AIMDeskRailView in the app */
@property (nonatomic, strong) NSTextField *card;        /* the card's NSTextView in the app */
@property (nonatomic, strong) NSTextField *noteHint;
@property (nonatomic, strong) NSTextField *note;
@property (nonatomic, strong) NSView *actions;          /* action-bar buttons, added in code */
@property (nonatomic, strong) NSTextView *composer;
@property (nonatomic, strong) NSTextField *undoLabel;
@property (nonatomic, strong) NSButton *undo;
- (IBAction)toggleRail:(id)sender;
- (IBAction)filterPulse:(id)sender;
- (IBAction)stillBlocked:(id)sender;
- (IBAction)goAheadWithout:(id)sender;
- (IBAction)prerequisites:(id)sender;
- (IBAction)takeOver:(id)sender;
- (IBAction)hotfix:(id)sender;
- (IBAction)dispatchBatch:(id)sender;
- (IBAction)endBatch:(id)sender;
- (IBAction)undo:(id)sender;
@end
