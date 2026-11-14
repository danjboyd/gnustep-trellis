/* TRGrid.h - CSS Grid support (engine-private).

   Copyright (C) 2026 Dan Boyd
   Licensed under the GNU LGPL, version 2.1 or later; see COPYING.LIB.
*/

#import <Foundation/Foundation.h>

/* Validation used by the style parser. */
BOOL TRGridValidateTrackList(NSString *value, BOOL singleTracksOnly);
BOOL TRGridValidateLine(NSString *value);
BOOL TRGridIsName(NSString *value);
/* grid-template-areas: "a a b" "c c b" -> rows of names; nil if invalid
   (ragged rows, or an area that is not a rectangle). */
NSArray<NSArray<NSString *> *> *TRGridParseAreas(NSString *value);
