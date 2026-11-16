/* AIMWorkVirtualOutlets.h - the owner contract for dogfood/work/Work-virtual.trellis.
   A stand-in for review, not AIManager's header. */
#import <AppKit/AppKit.h>
#import "TRVirtualBox.h"

@interface AIMWorkView : NSView
@property (nonatomic, strong) IBOutlet NSTextField *checks;
@property (nonatomic, strong) IBOutlet NSTextField *checks;
@property (nonatomic, strong) IBOutlet TRBoxView *detail;
@property (nonatomic, strong) IBOutlet NSTextField *detailHealth;
@property (nonatomic, strong) IBOutlet NSTextField *detailHealth;
@property (nonatomic, strong) IBOutlet NSTextField *detailMeta;
@property (nonatomic, strong) IBOutlet NSTextField *detailMeta;
@property (nonatomic, strong) IBOutlet NSTextField *detailName;
@property (nonatomic, strong) IBOutlet NSTextField *detailName;
@property (nonatomic, strong) IBOutlet NSTextField *detailStatus;
@property (nonatomic, strong) IBOutlet NSTextField *detailStatus;
@property (nonatomic, strong) IBOutlet NSTextField *goals;
@property (nonatomic, strong) IBOutlet NSButton *launch;
@property (nonatomic, strong) IBOutlet NSTextView *message;
@property (nonatomic, strong) IBOutlet NSTextView *message;
@property (nonatomic, strong) IBOutlet NSTextField *messageLabel;
@property (nonatomic, strong) IBOutlet NSButton *resume;
@property (nonatomic, strong) IBOutlet NSTextView *screen;
@property (nonatomic, strong) IBOutlet NSTextView *screen;
@property (nonatomic, strong) IBOutlet NSTextField *screenLabel;
@property (nonatomic, strong) IBOutlet NSButton *stop;
@property (nonatomic, strong) IBOutlet TRVirtualBox *wall;
@property (nonatomic, strong) IBOutlet TRBoxView *work;

- (IBAction)captureScreen:(id)sender;
- (IBAction)changeFocus:(id)sender;
- (IBAction)clearContext:(id)sender;
- (IBAction)editAgent:(id)sender;
- (IBAction)launchAgent:(id)sender;
- (IBAction)openTerminal:(id)sender;
- (IBAction)rebind:(id)sender;
- (IBAction)resumeAgent:(id)sender;
- (IBAction)retireAgent:(id)sender;
- (IBAction)showProject:(id)sender;
- (IBAction)stopAgent:(id)sender;
- (IBAction)useDraft:(id)sender;
@end
