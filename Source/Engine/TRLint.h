/* TRLint.h - layout checks over a frames.json tree (Foundation only).

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <Foundation/Foundation.h>

/* Checks a frame tree as written by trellis-render (each node: id, class,
   x, y, width, height relative to its parent; optional text, intrinsic,
   needed, overflow, position, hidden, children). Returns findings:
   {rule, severity ("error"|"warning"), id, path, message}.

   Rules: clipped-text, undersized, stretched, collapsed, overlap, overflow,
   offscreen, low-contrast (with resolved colours), and touch-target: a
   node marked "interactive" smaller than 24x24 px whose 24 px circle
   reaches another target (WCAG 2.2, 2.5.8, with its spacing exception). */
NSArray<NSDictionary *> *TRLintFrameTree(NSDictionary *root, double viewportWidth,
                                         double viewportHeight);
