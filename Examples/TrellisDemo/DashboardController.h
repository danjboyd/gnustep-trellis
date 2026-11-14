#import <AppKit/AppKit.h>

@interface DashboardController : NSObject
@property (nonatomic, strong) NSView *dashboard;
@property (nonatomic, strong) NSTextField *filter;
@property (nonatomic, strong) NSView *cards;
@property (nonatomic, strong) NSTextField *online, *asks, *done, *week;
@property (nonatomic, strong) NSProgressIndicator *builds;
@property (nonatomic, strong) NSTextField *log;
- (IBAction)refresh:(id)sender;
- (IBAction)showProject:(id)sender;
@end
