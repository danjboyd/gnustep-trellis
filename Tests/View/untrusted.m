/* untrusted (headless): TRMarkupDocument.untrusted, the hardened mode
   TrellisPreview --untrusted uses for files someone else sent.
   - <image src>: a file inside the document's folder loads; a missing one
     loads with no image; absolute, "..", "~", backslash (UNC), colon
     (drive), device-name, empty-component, symlink-out and non-regular
     (FIFO) paths fail the load; <image name> must be a plain name.
   - <view type>: standard classes only; any other class (here one defined
     in this test) becomes a placeholder and is never instantiated.
   - action= and <a action/href>: no target, no action, no URL; no outlets.
   - Templates built later from the document are hardened too.
   - The same markup, trusted, behaves as before.
   Prints UNTRUSTED OK. */
#import <AppKit/AppKit.h>
#import <sys/stat.h>
#import <unistd.h>
#ifdef _WIN32
#define TR_NO_POSIX_LINKS 1   /* no symlink()/mkfifo() on MinGW */
#endif
#import <objc/runtime.h>
#import "TRBoxView.h"
#import "TRLoader.h"
#import "TRSplitView.h"
#import "TRVirtualBox.h"
#import "TRAppKitCompat.h"

static int gFail = 0;
static void Expect(NSString *what, BOOL ok)
{
  printf("%s %s\n", ok ? "ok  " : "FAIL", [what UTF8String]);
  if (!ok) gFail++;
}

static int gEvilInits = 0;
@interface TRTestEvilView : NSView
@end
@implementation TRTestEvilView
- (instancetype)initWithFrame:(NSRect)f { gEvilInits++; return [super initWithFrame: f]; }
@end

@interface TRTestOwner : NSObject
@property (nonatomic, strong) NSView *ok;
@property (nonatomic) int hits;
- (void)hit:(id)sender;
@end
@implementation TRTestOwner
- (void)hit:(id)sender { (void)sender; self.hits++; }
@end

static NSString *gDir;   /* the document's folder */

static TRMarkupDocument *Doc(NSString *body, BOOL untrusted)
{
  NSString *src = [NSString stringWithFormat: @"<column>%@</column>", body];
  NSError *err = nil;
  TRMarkupDocument *d = [TRMarkupDocument documentWithString: src
                                                        name: [gDir stringByAppendingPathComponent: @"screen.trellis"]
                                                       error: &err];
  d.untrusted = untrusted;
  return d;
}

static NSView *First(TRBoxView *box)
{
  return [[box subviews] count] ? [box subviews][0] : nil;
}

/* Loads <image src="src"> (or name=); returns the error text, or nil and
   the image view in *iv. */
static NSString *LoadImage(NSString *attr, NSString *value, BOOL untrusted, NSImageView **iv)
{
  NSString *esc = [[value stringByReplacingOccurrencesOfString: @"&" withString: @"&amp;"]
                    stringByReplacingOccurrencesOfString: @"\"" withString: @"&quot;"];
  TRMarkupDocument *d = Doc([NSString stringWithFormat: @"<image %@=\"%@\"/>", attr, esc], untrusted);
  NSError *err = nil;
  TRBoxView *box = [TRLoader loadDocument: d owner: nil error: &err];
  if (box == nil) return [err localizedDescription] ?: @"(no error text)";
  if (iv) *iv = (NSImageView *)First(box);
  return nil;
}

static void ExpectRejected(NSString *src, NSString *why)
{
  NSString *e = LoadImage(@"src", src, YES, NULL);
  Expect([NSString stringWithFormat: @"untrusted src \"%@\" rejected (%@)", src, e ?: @"loaded"],
         e != nil && [e rangeOfString: why].location != NSNotFound);
}

/* Rejected for one of two reasons (GNUstep counts "\\host" and "C:/"
   as absolute paths; other platforms reach the backslash/colon rule). */
static void ExpectRejected2(NSString *src, NSString *why1, NSString *why2)
{
  NSString *e = LoadImage(@"src", src, YES, NULL);
  Expect([NSString stringWithFormat: @"untrusted src \"%@\" rejected (%@)", src, e ?: @"loaded"],
         e != nil && ([e rangeOfString: why1].location != NSNotFound || [e rangeOfString: why2].location != NSNotFound));
}

static void WritePNG(NSString *path)
{
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 4 pixelsHigh: 4
    bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSCalibratedRGBColorSpace
    bytesPerRow: 0 bitsPerPixel: 0];
  memset([rep bitmapData], 0x80, [rep bytesPerRow] * 4);
  [[rep representationUsingType: NSBitmapImageFileTypePNG properties: @{}] writeToFile: path atomically: YES];
}

int main(void)
{
  @autoreleasepool
    {
      /* AppKit too: without NSApp, -sendAction:to: reaches nothing. */
      [NSApplication sharedApplication];
      NSFileManager *fm = [NSFileManager defaultManager];
      NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat: @"trellis-untrusted-%d", getpid()]];
      gDir = [root stringByAppendingPathComponent: @"doc"];
      [fm createDirectoryAtPath: [gDir stringByAppendingPathComponent: @"img"]
    withIntermediateDirectories: YES attributes: nil error: NULL];
      WritePNG([gDir stringByAppendingPathComponent: @"img/ok.png"]);
      WritePNG([root stringByAppendingPathComponent: @"secret.png"]);
#ifndef TR_NO_POSIX_LINKS
      symlink([[root stringByAppendingPathComponent: @"secret.png"] fileSystemRepresentation],
              [[gDir stringByAppendingPathComponent: @"link.png"] fileSystemRepresentation]);
      symlink("img/ok.png", [[gDir stringByAppendingPathComponent: @"inner.png"] fileSystemRepresentation]);
      mkfifo([[gDir stringByAppendingPathComponent: @"fifo.png"] fileSystemRepresentation], 0600);
      /* A folder link out (the Windows-junction / failed-realpath case). */
      symlink([root fileSystemRepresentation], [[gDir stringByAppendingPathComponent: @"pics"] fileSystemRepresentation]);
#endif
      [@"not an image" writeToFile: [gDir stringByAppendingPathComponent: @"notes.png"] atomically: YES
                          encoding: NSUTF8StringEncoding error: NULL];
      {
        /* A 60000 x 60000 PNG header: a tiny file that would decode to gigabytes. */
        unsigned char bomb[33] = { 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 'I', 'H', 'D', 'R',
                                   0, 0, 0xea, 0x60, 0, 0, 0xea, 0x60, 8, 6, 0, 0, 0, 0, 0, 0, 0 };
        [[NSData dataWithBytes: bomb length: sizeof bomb] writeToFile: [gDir stringByAppendingPathComponent: @"bomb.png"]
                                                           atomically: YES];
      }

      /* Images: what passes. */
      NSImageView *iv = nil;
      NSString *e = LoadImage(@"src", @"img/ok.png", YES, &iv);
      Expect(@"untrusted src inside the folder loads", e == nil && [iv image] != nil);
#ifndef TR_NO_POSIX_LINKS
      ExpectRejected(@"inner.png", @"symbolic link");   /* no links at all, even inside */
#endif
      e = LoadImage(@"src", @"missing.png", YES, &iv);
      Expect(@"untrusted src of a missing file loads, with no image", e == nil && [iv image] == nil);

      /* Images: what doesn't. */
      ExpectRejected([root stringByAppendingPathComponent: @"secret.png"], @"absolute");
      ExpectRejected(@"../secret.png", @"'..'");
      ExpectRejected(@"img/../../secret.png", @"'..'");
      ExpectRejected2(@"\\\\host\\share\\x.png", @"backslash", @"absolute");
      ExpectRejected(@"//host/share/x.png", @"absolute");
      ExpectRejected2(@"C:/Windows/x.png", @"colon", @"absolute");
      ExpectRejected2(@"img\\..\\..\\secret.png", @"backslash", @"absolute");
      ExpectRejected(@"x.png:stream", @"colon");
      ExpectRejected(@"~/x.png", @"~");
      ExpectRejected(@"img//ok.png", @"empty");
      ExpectRejected(@"./img/ok.png", @"'.'");
      ExpectRejected(@".../secret.png", @"ending in '.'");
      ExpectRejected(@"img/ok.png.", @"ending in '.'");
      ExpectRejected(@"img /ok.png", @"space");
      ExpectRejected(@"notes.png", @"not a PNG, JPEG or GIF");
      ExpectRejected(@"bomb.png", @"too large");
      ExpectRejected(@"COM\u00b9.png", @"device");
      ExpectRejected(@"NUL", @"device");
      ExpectRejected(@"img/com1.png", @"device");
#ifndef TR_NO_POSIX_LINKS
      ExpectRejected(@"link.png", @"symbolic link");
      ExpectRejected(@"pics/secret.png", @"symbolic link");
      ExpectRejected(@"fifo.png", @"regular");
#endif
      e = LoadImage(@"name", @"../secret", YES, NULL);
      Expect(@"untrusted <image name> with a path rejected", e != nil);
      e = LoadImage(@"name", @"NSApplicationIcon", YES, NULL);
      Expect(@"untrusted <image name> plain name loads", e == nil);

      /* Trusted documents are unchanged. */
      e = LoadImage(@"src", @"../secret.png", NO, &iv);
      Expect(@"trusted src outside the folder still loads", e == nil && [iv image] != nil);

      /* View classes. */
      NSError *err = nil;
      TRBoxView *box = [TRLoader loadDocument: Doc(@"<view type=\"TRTestEvilView\"/><view type=\"NSTextField\"/>", YES)
                                        owner: nil error: &err];
      Expect(@"untrusted: an app class is not instantiated", box != nil && gEvilInits == 0
             && ![[box subviews][0] isKindOfClass: [TRTestEvilView class]]);
      Expect(@"untrusted: a standard class (NSTextField) is", box != nil
             && [[box subviews][1] isMemberOfClass: [NSTextField class]]);
      box = [TRLoader loadDocument: Doc(@"<view type=\"TRTestEvilView\"/>", NO) owner: nil error: &err];
      Expect(@"trusted: the app class is instantiated", gEvilInits == 1
             && [First(box) isKindOfClass: [TRTestEvilView class]]);

      /* Actions, links, outlets. */
      NSString *ctl = @"<button id=\"ok\" action=\"hit:\">Go</button>"
                      @"<label id=\"lk\" no-outlet=\"yes\">See <a action=\"hit:\">this</a> and <a href=\"https://example.invalid/\">that</a></label>";
      TRTestOwner *owner = [TRTestOwner new];
      box = [TRLoader loadDocument: Doc(ctl, YES) owner: owner error: &err];
      NSButton *b = (NSButton *)[TRLoader viewWithIdentifier: @"ok" inView: box];
      Expect(@"untrusted: the button has no action and no target", b != nil && [b action] == NULL && [b target] == nil);
      [b performClick: nil];
      Expect(@"untrusted: clicking the button reaches nothing", owner.hits == 0);
      Expect(@"untrusted: no outlet is set", owner.ok == nil);
      TRRichLabel *rl = (TRRichLabel *)[TRLoader viewWithIdentifier: @"lk" inView: box];
      NSString *plain = [rl plainText];
      NSUInteger ai = [plain rangeOfString: @"this"].location, hi = [plain rangeOfString: @"that"].location;
      BOOL a1 = [rl activateLinkAtCharacterIndex: ai], a2 = [rl activateLinkAtCharacterIndex: hi];
      Expect(@"untrusted: links send no action and open no URL", rl.untrusted && !a1 && !a2 && owner.hits == 0
             && rl.linkTarget == nil);
      Expect(@"untrusted: the clicked href is still recorded", [rl.clickedLink isEqualToString: @"https://example.invalid/"]);
      box = [TRLoader loadDocument: Doc(@"<button action=\"terminate:\">Quit</button>", YES) owner: nil error: &err];
      Expect(@"untrusted, no owner: a responder-chain action is not wired", [(NSButton *)First(box) action] == NULL);

      TRTestOwner *owner2 = [TRTestOwner new];
      box = [TRLoader loadDocument: Doc(ctl, NO) owner: owner2 error: &err];
      b = (NSButton *)[TRLoader viewWithIdentifier: @"ok" inView: box];
      [b performClick: nil];
      Expect([NSString stringWithFormat: @"trusted: the action and outlet still work (box %d, hits %d, outlet %d, err %@)",
              box != nil, owner2.hits, owner2.ok == b, [err localizedDescription]], owner2.hits == 1 && owner2.ok == b);
      box = [TRLoader loadDocument: Doc(@"<button action=\"terminate:\">Quit</button>", NO) owner: nil error: &err];
      Expect([NSString stringWithFormat: @"trusted, no owner: the action is still wired (unchanged) (box %d, action %@)",
              box != nil, NSStringFromSelector([(NSButton *)First(box) action])],
             sel_isEqual([(NSButton *)First(box) action], @selector(terminate:)));

      /* No link attribute (AppKit could open it), no autosave defaults. */
      box = [TRLoader loadDocument: Doc(@"<label id=\"lk\">x <a href=\"https://example.invalid/\">y</a></label>"
                                        @"<split id=\"sp\" autosave=\"TRUntrustedTest\"><column/><column/></split>", YES)
                             owner: nil error: &err];
      rl = (TRRichLabel *)[TRLoader viewWithIdentifier: @"lk" inView: box];
      NSAttributedString *as = [rl attributedStringValue];
      BOOL anyLink = NO;
      for (NSUInteger i = 0; i < [as length]; i++)
        if ([as attribute: NSLinkAttributeName atIndex: i effectiveRange: NULL]) anyLink = YES;
      Expect(@"untrusted: link text carries no NSLinkAttributeName", rl != nil && !anyLink);
      TRSplitView *sp = (TRSplitView *)[TRLoader viewWithIdentifier: @"sp" inView: box];
      Expect(@"untrusted: <split autosave> is ignored", sp != nil && sp.autosave == nil);

      /* var() growth is capped. */
      NSMutableString *css = [NSMutableString stringWithString: @"<style>.c { --a0: xxxxxxxxxx; "];
      for (int l = 1; l <= 7; l++)
        {
          [css appendFormat: @"--a%d:", l];
          for (int k = 0; k < 10; k++) [css appendFormat: @" var(--a%d)", l - 1];
          [css appendString: @"; "];
        }
      [css appendString: @"width: var(--a7); }</style><label class=\"c\">x</label>"];
      err = nil;
      NSDate *t0 = [NSDate date];
      TRMarkupDocument *bd = [TRMarkupDocument documentWithString: [NSString stringWithFormat: @"<column>%@</column>", css]
                                                             name: [gDir stringByAppendingPathComponent: @"bomb.trellis"]
                                                            error: &err];
      if (bd) { bd.untrusted = YES; box = [TRLoader loadDocument: bd owner: nil error: &err]; }
      else box = nil;
      Expect([NSString stringWithFormat: @"var() expansion bomb fails fast (%.2fs: %@)", -[t0 timeIntervalSinceNow],
              [err localizedDescription]],
             /* Over the cap, the custom property is dropped where it is
                defined (so the use reports it undefined), or the use itself
                fails: either way, fast. */
             box == nil && ([[err localizedDescription] rangeOfString: @"64 KB"].location != NSNotFound
                            || [[err localizedDescription] rangeOfString: @"is not defined"].location != NSNotFound)
             && -[t0 timeIntervalSinceNow] < 5);

      /* Sample row counts are capped. */
      box = [TRLoader loadDocument: Doc(@"<virtual id=\"list\" template=\"row\" estimated-size=\"30\">"
                                        @"<template id=\"row\"><row><label id=\"t\">x</label></row></template></virtual>", YES)
                             owner: nil error: &err];
      BOOL applied = [TRLoader applySample: @{@"list": @{@"items": @[@{@"_repeat": @1000000000, @"items": @[@{}]}],
                                                         @"repeat": @1000000000000}} toView: box error: &err];
      TRVirtualBox *vb = (TRVirtualBox *)[TRLoader viewWithIdentifier: @"list" inView: box];
      NSInteger rows = [[vb dataSource] numberOfItemsInVirtualBox: vb];
      Expect([NSString stringWithFormat: @"sample repeat is capped at a million rows (%ld)", (long)rows],
             applied && rows == 1000000);

      /* Wrong-typed sample values are load errors, not exceptions later. */
      box = [TRLoader loadDocument: Doc(@"<button id=\"b\">Go</button><popup id=\"p\"/>"
                                        @"<virtual id=\"list\" template=\"row\" estimated-size=\"30\">"
                                        @"<template id=\"row\"><row><label id=\"t\">x</label></row></template></virtual>", YES)
                             owner: nil error: &err];
      BOOL threw = NO, ok1 = YES, ok2 = YES, ok3 = YES;
      @try
        {
          err = nil;
          ok1 = [TRLoader applySample: @{@"b": @{@"title": @5}} toView: box error: &err];
          ok2 = [TRLoader applySample: @{@"p": @[@"one", @2]} toView: box error: &err];
          ok3 = [TRLoader applySample: @{@"list": @{@"items": @[@"x", @5, @{@"_template": @7, @"_repeat": @[]}],
                                                    @"repeat": @[], @"scroll-to": @{}}} toView: box error: &err];
          vb = (TRVirtualBox *)[TRLoader viewWithIdentifier: @"list" inView: box];
          [vb setFrame: NSMakeRect(0, 0, 200, 200)];
          [box setFrame: NSMakeRect(0, 0, 200, 300)];
          [box layoutTrellis];
        }
      @catch (NSException *ex) { threw = YES; NSLog(@"threw: %@", ex); }
      Expect(@"wrong-typed sample values are refused without an exception", !threw && !ok1 && !ok2 && ok3);

      /* The sample reader keeps the same rules. */
      NSError *rerr = nil;
      NSData *sd = [TRLoader untrustedContentsOfFile: @"link.png" inFolder: gDir maxLength: 1 << 20 error: &rerr];
      Expect(@"untrustedContentsOfFile: refuses a symbolic link", sd == nil && rerr != nil);
      sd = [TRLoader untrustedContentsOfFile: @"nope.json" inFolder: gDir maxLength: 1 << 20 error: &rerr];
      Expect(@"untrustedContentsOfFile: a missing file is nil with no error", sd == nil && rerr == nil);
      sd = [TRLoader untrustedContentsOfFile: @"img/ok.png" inFolder: gDir maxLength: 10 error: &rerr];
      Expect(@"untrustedContentsOfFile: over the limit is refused", sd == nil && rerr != nil);

      /* Templates built later from an untrusted document. */
      NSString *tsrc = @"<column><label>x</label></column>"
                       @"<template id=\"row\"><row><image src=\"../secret.png\"/></row></template>";
      TRMarkupDocument *td = [TRMarkupDocument documentWithString: tsrc
                                 name: [gDir stringByAppendingPathComponent: @"t.trellis"] error: &err];
      td.untrusted = YES;
      err = nil;
      NSView *tv = [TRLoader instantiateTemplate: @"row" ofDocument: td owner: nil error: &err];
      Expect(@"untrusted: a template instance is hardened too", tv == nil && err != nil);

      [fm removeItemAtPath: root error: NULL];
      printf(gFail ? "UNTRUSTED FAIL\n" : "UNTRUSTED OK\n");
      return gFail ? 1 : 0;
    }
}
