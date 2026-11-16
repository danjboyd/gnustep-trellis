/* The owner contract for dogfood/desk/*.trellis: the outlets and actions
   AIManager's AIMTriageDeskView would expose with its card drawn by
   Trellis (G3-G7). A stand-in for review only. It is not AIManager's
   header, and nothing here touches the AIManager repo. */
#import <AppKit/AppKit.h>

@interface AIMTriageDeskView : NSView
/* Shell */
@property (nonatomic, strong) NSView *desk;
@property (nonatomic, strong) NSView *topBar;
@property (nonatomic, strong) NSButton *railToggle;     /* below 640px: opens the rail */
@property (nonatomic, strong) NSView *pulse;            /* AIMDeskPulseParts chips, in code */
@property (nonatomic, strong) NSTextField *oldestWait;
@property (nonatomic, strong) NSTextField *unheard;
@property (nonatomic, strong) NSTextField *filter;
@property (nonatomic, strong) NSView *rail;             /* AIMDeskRailView in the app */
/* Card header (G4) */
@property (nonatomic, strong) NSView *card;
@property (nonatomic, strong) NSView *cardHeader;
@property (nonatomic, strong) NSTextField *gateLine;
@property (nonatomic, strong) NSTextField *cardTitle;
@property (nonatomic, strong) NSTextField *requester;
@property (nonatomic, strong) NSTextField *lastHeard;
/* Card body: one per gate; sections filled in code */
@property (nonatomic, strong) NSView *cardBody;
@property (nonatomic, strong) NSView *assignees;        /* Intake: radios 1-9, in code */
@property (nonatomic, strong) NSView *tracks;           /* Intake: Standard / Hotfix / Project */
@property (nonatomic, strong) NSView *steps;            /* Verify: Done / Changed rows */
@property (nonatomic, strong) NSView *progress;         /* Project: one segment per item */
@property (nonatomic, strong) NSView *workItems;        /* Project: the table rows */
/* The decision bar, pinned under the card's scroller */
@property (nonatomic, strong) NSView *decision;
@property (nonatomic, strong) NSTextField *note;
@property (nonatomic, strong) NSView *actions;          /* AIMDeskAction buttons, in code */
@property (nonatomic, strong) NSTextField *actionHint;
/* Reply draft (G5) */
@property (nonatomic, strong) NSView *reply;
@property (nonatomic, strong) NSTextField *replyMeta;
@property (nonatomic, strong) NSTextField *replyBody;
@property (nonatomic, strong) NSButton *sendOnly;
@property (nonatomic, strong) NSButton *redraft;
/* Drawer (closed by default) */
@property (nonatomic, strong) NSView *drawer;
@property (nonatomic, strong) NSPopUpButton *drawerTabs;   /* Ticket, Timeline, Agent chat, Requester, Related, Trust */
@property (nonatomic, strong) NSTextField *chatInput;
@property (nonatomic, strong) NSView *undoBar;           /* hidden until an action is held */
@property (nonatomic, strong) NSTextField *undoLabel;
@property (nonatomic, strong) NSButton *undo;
- (IBAction)toggleRail:(id)sender;
- (IBAction)filterPulse:(id)sender;
- (IBAction)pickAssignee:(id)sender;
- (IBAction)pickTrack:(id)sender;
- (IBAction)deskAction:(id)sender;                      /* tag = index into the actions */
- (IBAction)expandSection:(id)sender;                   /* Alternatives / Evidence / Change detail */
- (IBAction)sendOnly:(id)sender;
- (IBAction)redraft:(id)sender;
- (IBAction)drawerTab:(id)sender;
- (IBAction)closeDrawer:(id)sender;
- (IBAction)sendToAgent:(id)sender;
- (IBAction)sendAsRevision:(id)sender;
- (IBAction)undo:(id)sender;
@end
