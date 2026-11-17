/* AppKit names Trellis uses in their current (macOS 10.12+) spelling. GNUstep
   gui has most of them; these map the ones it lacks to the old spellings, so
   the sources build without deprecation warnings on macOS and unchanged on
   GNUstep. Import after AppKit. Private: not installed. */
#ifndef TR_APPKIT_COMPAT_H
#define TR_APPKIT_COMPAT_H
#import <AppKit/AppKit.h>

#ifdef GNUSTEP
#define NSBezelStyleRounded      NSRoundedBezelStyle
#define NSButtonTypeSwitch       NSSwitchButton
#define NSButtonTypeRadio        NSRadioButton
#define NSBitmapImageFileTypePNG NSPNGFileType
#endif

#endif
