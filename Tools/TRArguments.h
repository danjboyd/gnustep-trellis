/* TRArguments.h: command-line arguments as NSStrings, on every platform.

   Copyright (C) 2026 Dan Boyd

   main's argv is in the system's multibyte encoding. That's UTF-8 on
   Linux and macOS, but on Windows it's the ANSI code page, where a path
   such as "Façade ñ.trellis" either isn't valid UTF-8 (stringWithUTF8String
   returns nil) or decodes to the wrong letters. NSProcessInfo's arguments
   come from the wide command line there (GetCommandLineW), so use them,
   and fall back to argv only if the two disagree in count. */

#import <Foundation/Foundation.h>

static inline NSArray<NSString *> *TRArguments(int argc, const char **argv)
{
  NSArray *pa = [[NSProcessInfo processInfo] arguments];
  if ((int)[pa count] == argc) return pa;
  NSMutableArray *out = [NSMutableArray arrayWithCapacity: argc];
  for (int i = 0; i < argc; i++)
    [out addObject: [NSString stringWithUTF8String: argv[i]] ?: @""];
  return out;
}
