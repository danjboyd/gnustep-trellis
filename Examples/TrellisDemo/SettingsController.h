#import <AppKit/AppKit.h>

@interface SettingsController : NSObject
@property (nonatomic, strong) NSView *settings;
@property (nonatomic, strong) NSTextField *displayName;
@property (nonatomic, strong) NSPopUpButton *theme;
@property (nonatomic, strong) NSPopUpButton *density;
@property (nonatomic, strong) NSButton *autoUpdate;
@property (nonatomic, strong) NSSlider *fontSize;
- (IBAction)cancel:(id)sender;
- (IBAction)save:(id)sender;
@end
