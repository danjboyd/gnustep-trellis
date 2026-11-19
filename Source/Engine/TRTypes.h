/* TRTypes.h - basic value types for the Trellis layout engine.

   Copyright (C) 2026 Dan Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
   Lesser General Public License for more details.
*/

#ifndef TRELLIS_TRTYPES_H
#define TRELLIS_TRTYPES_H

#import <Foundation/Foundation.h>
#include <math.h>

/* The engine is Foundation-only and uses double throughout, so it builds
   unchanged on GNUstep and on Apple Foundation (no CoreGraphics/AppKit). */
typedef double TRFloat;

/* NAN means "undefined / unconstrained" everywhere in the engine. */
#define TRUndefined ((TRFloat)NAN)
static inline BOOL TRIsUndefined(TRFloat f) { return isnan(f); }
static inline BOOL TRIsDefined(TRFloat f) { return !isnan(f); }

typedef struct { TRFloat width, height; } TRSize;
typedef struct { TRFloat x, y; } TRPoint;
typedef struct { TRFloat x, y, width, height; } TRRect;

static inline TRSize TRSizeMake(TRFloat w, TRFloat h) { TRSize s = { w, h }; return s; }
static inline TRRect TRRectMake(TRFloat x, TRFloat y, TRFloat w, TRFloat h)
{ TRRect r = { x, y, w, h }; return r; }

typedef NS_ENUM(unsigned char, TRUnit) {
  TRUnitUndefined = 0,  /* e.g. max-width: none */
  TRUnitAuto,
  TRUnitPoint,          /* CSS px; 1px = 1 point */
  TRUnitPercent,
  /* Intrinsic size keywords (css-sizing-3/4), for width, height, their
     min/max and flex-basis only. */
  TRUnitMinContent,
  TRUnitMaxContent,
  TRUnitFitContent,
  TRUnitStretch,
  /* calc() of lengths and percentages, reduced to value px + pct % */
  TRUnitCalc,
  /* min()/max()/clamp() mixing px with %: value is an index of an
     interned expression, evaluated by TRMathEval at layout time. */
  TRUnitMath
};

static inline BOOL TRUnitIsIntrinsic(TRUnit u) { return u >= TRUnitMinContent && u <= TRUnitStretch; }

/* A CSS length-percentage-or-auto. pct is the percentage part of a calc()
   (unit TRUnitCalc); value is its px part. */
typedef struct { TRFloat value; TRUnit unit; TRFloat pct; } TRValue;

/* A percentage, or a calc() that may have one: resolves against a
   reference, and is indefinite when the reference is. */
static inline BOOL TRIsPct(TRUnit u) { return u == TRUnitPercent || u == TRUnitCalc || u == TRUnitMath; }

/* The interned min()/max()/clamp() expression at index, at a reference
   length; NAN when the reference is indefinite. */
TRFloat TRMathEval(int index, TRFloat ref);

static inline TRValue TRPx(TRFloat v) { TRValue r = { v, TRUnitPoint }; return r; }
static inline TRValue TRPercent(TRFloat v) { TRValue r = { v, TRUnitPercent }; return r; }
static inline TRValue TRAutoValue(void) { TRValue r = { 0, TRUnitAuto }; return r; }
static inline TRValue TRNoneValue(void) { TRValue r = { 0, TRUnitUndefined }; return r; }
#define TRAuto TRAutoValue()
#define TRNone TRNoneValue()

static inline BOOL TRValueEqual(TRValue a, TRValue b)
{
  if (a.unit != b.unit) return NO;
  if (a.unit == TRUnitPoint || a.unit == TRUnitPercent || a.unit == TRUnitMath) return a.value == b.value;
  if (a.unit == TRUnitCalc) return a.value == b.value && a.pct == b.pct;
  return YES;
}

/* A px, percentage or calc() length at a reference length: NAN for a
   percentage part of an indefinite reference, and for any other unit. */
static inline TRFloat TRValueAt(TRValue v, TRFloat ref)
{
  switch (v.unit)
    {
      case TRUnitPoint: return v.value;
      case TRUnitPercent: return isnan(ref) ? (TRFloat)NAN : v.value * ref / 100;
      case TRUnitCalc: return isnan(ref) ? (TRFloat)NAN : v.value + v.pct * ref / 100;
      case TRUnitMath: return TRMathEval((int)v.value, ref);
      default: return (TRFloat)NAN;
    }
}

typedef NS_ENUM(unsigned char, TREdge) {
  TREdgeLeft = 0, TREdgeTop, TREdgeRight, TREdgeBottom
};

/* display: block is a Trellis convenience, not CSS block flow: it lays out
   like flex with flex-direction: column (and the default align-items:
   stretch), whatever flex-direction says. */
typedef NS_ENUM(unsigned char, TRDisplay) { TRDisplayFlex = 0, TRDisplayNone, TRDisplayBlock, TRDisplayGrid,
  TRDisplayContents /* no box: its children are laid out as its parent's */ };
typedef NS_ENUM(unsigned char, TRPosition) {
  TRPositionRelative = 0, TRPositionStatic, TRPositionAbsolute
};
typedef NS_ENUM(unsigned char, TRDirection) {
  TRDirectionInherit = 0, TRDirectionLTR, TRDirectionRTL
};
typedef NS_ENUM(unsigned char, TRFlexDirection) {
  TRFlexDirectionRow = 0, TRFlexDirectionRowReverse,
  TRFlexDirectionColumn, TRFlexDirectionColumnReverse
};
typedef NS_ENUM(unsigned char, TRFlexWrap) {
  TRFlexWrapNoWrap = 0, TRFlexWrapWrap, TRFlexWrapWrapReverse
};
/* Shared by justify-content, align-items, align-self and align-content.
   Not every value is meaningful for every property. */
typedef NS_ENUM(unsigned char, TRAlign) {
  TRAlignAuto = 0,      /* align-self only */
  TRAlignNormal,        /* initial value: behaves as stretch (align) or flex-start (justify) */
  TRAlignFlexStart,
  TRAlignFlexEnd,
  TRAlignStart,
  TRAlignEnd,
  TRAlignCenter,
  TRAlignStretch,
  TRAlignBaseline,
  TRAlignSpaceBetween,
  TRAlignSpaceAround,
  TRAlignSpaceEvenly,
  TRAlignLeft,          /* justify-* only: physical */
  TRAlignRight,
  TRAlignLastBaseline   /* approximated as 'end' (its fallback) */
};
typedef NS_ENUM(unsigned char, TROverflow) {
  TROverflowVisible = 0, TROverflowHidden, TROverflowScroll, TROverflowAuto
};
typedef NS_ENUM(unsigned char, TRBoxSizing) {
  TRBoxSizingContentBox = 0, TRBoxSizingBorderBox
};

/* How a size constraint passed to a measure function is to be read
   (the same model as Yoga):
   - Undefined: no constraint, report the max-content size;
   - Exactly:   the size is fixed, report it;
   - AtMost:    report the content size, but no more than this (fit-content). */
typedef NS_ENUM(unsigned char, TRMeasureMode) {
  TRMeasureModeUndefined = 0, TRMeasureModeExactly, TRMeasureModeAtMost
};

#endif
