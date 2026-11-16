/* The owner contract for dogfood/AskDetail.trellis: the outlets and actions
   AIManager's AIMAskDetailView would expose if its -layoutContent were
   replaced by the Trellis spec. A stand-in for review only. It is not
   AIManager's header, and nothing here touches the AIManager repo.

   trellis-lint dogfood/AskDetail.trellis --owner dogfood/AIMAskDetailOutlets.h */
#import <AppKit/AppKit.h>

@interface AIMAskDetailView : NSView
/* Header */
@property (nonatomic, strong) NSView *askDetail;
@property (nonatomic, strong) NSTextField *context;     /* project › agent */
@property (nonatomic, strong) NSTextField *title;
@property (nonatomic, strong) NSTextField *meta;        /* kind · blocks: … */
@property (nonatomic, strong) NSTextField *delivery;
@property (nonatomic, strong) NSView *links;            /* link buttons, added in code */
/* Body and the ask-terminal strip (a planned app feature) */
@property (nonatomic, strong) NSTextField *body;        /* an NSTextView in the app */
@property (nonatomic, strong) NSView *terminalStrip;
/* The recommended / chosen option */
@property (nonatomic, strong) NSView *pick;
@property (nonatomic, strong) NSTextField *pickLabel;   /* Recommended / Your pick / Answered */
@property (nonatomic, strong) NSTextField *pickTitle;
@property (nonatomic, strong) NSTextField *pickDetail;
@property (nonatomic, strong) NSButton *doIt;
/* The other options (buttons added in code) */
@property (nonatomic, strong) NSView *otherOptions;
@property (nonatomic, strong) NSView *optionButtons;
/* Reply */
@property (nonatomic, strong) NSTextField *replyLabel;
@property (nonatomic, strong) NSTextView *reply;
@property (nonatomic, strong) NSView *attachments;
@property (nonatomic, strong) NSTextField *attachmentName;
/* Actions */
@property (nonatomic, strong) NSButton *sendReply;
@property (nonatomic, strong) NSPopUpButton *snooze;
@property (nonatomic, strong) NSButton *dismiss;
@property (nonatomic, strong) NSTextField *status;
@property (nonatomic, strong) NSButton *resumeAgent;
/* Thread and follow-up */
@property (nonatomic, strong) NSTextField *threadLabel;
@property (nonatomic, strong) NSTextField *thread;      /* a thread view in the app */
@property (nonatomic, strong) NSTextField *followUp;
- (IBAction)doIt:(id)sender;
- (IBAction)sendReply:(id)sender;
- (IBAction)snooze:(id)sender;
- (IBAction)dismiss:(id)sender;
- (IBAction)openAttachment:(id)sender;
- (IBAction)clearAttachment:(id)sender;
- (IBAction)resumeAgent:(id)sender;
- (IBAction)openTerminal:(id)sender;
- (IBAction)agentSettings:(id)sender;
- (IBAction)sendFollowUp:(id)sender;
- (IBAction)openLink:(id)sender;
- (IBAction)chooseOption:(id)sender;
@end
