/* Trellis conformance runner: engine adapter interface.
 *
 * Copyright (C) 2026 Trellis contributors.  LGPL-2.1-or-later.
 *
 * An engine adapter turns one JSON case (see README.md) into a laid-out
 * frame tree.  The runner owns case loading, skipping, comparison and
 * reporting, so adapters stay small: one for Trellis (TRConfEngineTrellis.m)
 * and one reference adapter for Yoga (reference/TRConfEngineYoga.mm), which
 * is used to validate the imported cases themselves.
 */
#import <Foundation/Foundation.h>

@protocol TRConfEngine <NSObject>
/* Short name printed in the report, e.g. "trellis" or "yoga". */
- (NSString *)engineName;
/* Feature tags (from a case's "requires") this engine does not support.
 * Cases requiring any of them are reported as skipped, not failed. */
- (NSSet *)unsupportedFeatures;
/* Lay out the case and return a frame tree with the same shape as
 * case[@"root"]: @{x, y, width, height, children: [...]} (numbers, frames
 * relative to the parent's border box).  Return nil and set *error if the
 * case can't be built (counted as a failure with that message). */
- (NSDictionary *)layoutCase:(NSDictionary *)testCase error:(NSString **)error;
@end

/* Ahem-style measurer shared by adapters for "measure":{"text":...} leaves.
 * Glyphs are charWidth wide, lines wrap greedily at spaces, each line is
 * lineHeight tall.  Width modes follow Yoga/Trellis: 0 = undefined
 * (max-content), 1 = exactly, 2 = at-most. */
#ifdef __cplusplus
extern "C" {
#endif
typedef struct { double width, height; } TRConfSize;
TRConfSize TRConfMeasure(NSDictionary *measure, double width, int widthMode,
                         double height, int heightMode);

int TRConfRunMain(id<TRConfEngine> engine, int argc, const char **argv);
#ifdef __cplusplus
}
#endif
