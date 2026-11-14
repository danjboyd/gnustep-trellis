/* The owner of AskDetail.trellis: outlets are matched to ids, actions to
   action= attributes (trellis-lint AskDetail.trellis --owner AskDetailController.h). */
#import <AppKit/AppKit.h>

@interface AskDetailController : NSObject
@property (nonatomic, strong) NSView *ask;
@property (nonatomic, strong) NSTextField *kind;
@property (nonatomic, strong) NSTextField *title;
@property (nonatomic, strong) NSTextField *age;
@property (nonatomic, strong) NSTextField *agent;
@property (nonatomic, strong) NSTextField *blocks;
@property (nonatomic, strong) NSTextField *body;
@property (nonatomic, strong) NSView *options;
@property (nonatomic, strong) NSButton *approve;
@property (nonatomic, strong) NSButton *alternative;
@property (nonatomic, strong) NSButton *defer;
@property (nonatomic, strong) NSTextField *reply;
@property (nonatomic, strong) NSButton *send;
- (IBAction)approve:(id)sender;
- (IBAction)chooseAlternative:(id)sender;
- (IBAction)deferAsk:(id)sender;
- (IBAction)sendReply:(id)sender;
@end
