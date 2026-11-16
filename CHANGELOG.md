# Changelog

Trellis follows semantic versioning once 1.0 ships; before that, a minor
version may change the API listed in docs/api.md, and says so here.

## Unreleased

- **Added:** keyboard focus order. The outermost TRBoxView links its
  controls into a nextKeyView loop in document order after every layout,
  skipping hidden ones (container queries included); `tabindex="N"`
  overrides it and `tabindex="-1"` leaves a control out. API:
  `managesKeyViewLoop`, `-recalculateTrellisKeyViewLoop`, `firstKeyView`,
  `TRSetTabIndex`/`TRTabIndex`.
- **Fixed:** container queries inside a `<scroll>` now test the nearest
  container outside the scroller. They used to test the scroller's
  content box, so a classic, space-taking scroller shifted the
  breakpoint (Gumdrop at 520px; reported by a pilot app).

## 0.1.1 (2026-11-16)

Dark appearance and themes. In Dark (macOS) or a dark GNUstep theme, a
fixed CSS background kept its light colour while unstyled text turned
light, so text vanished.

- **CSS system colours:**
  - `Canvas`, `CanvasText`, `Field`, `FieldText`, `ButtonFace`, `ButtonText`,
    `ButtonBorder`, `GrayText`, `Highlight`, `HighlightText`, `SelectedItem`,
    `SelectedItemText`, `AccentColor`, `AccentColorText`, `LinkText`, `Mark`
    and `MarkText`;
  - plus `-tr-window-background`, `-tr-separator`, `-tr-secondary-text` and
    `-tr-error`.

  They resolve to AppKit's dynamic colours at draw time, so they follow the
  appearance and the GNUstep theme.
- **trellis-lint `colour-pair`:** warns about a fixed background with text
  that follows the system, or a fixed text colour over a system background.
- **trellis-render:** `--appearance light|dark` (DarkAqua on macOS,
  Adwaita's colour scheme on GNUstep). It passes `-DefaultsKey value`
  through, and dumps the resolved colours (`background`, `textColor`,
  `windowBackground`).
- **Render lint `low-contrast`:** text under 3:1 against its resolved
  background.
- **Specs:** the demos and dogfood specs now use system colours. The
  Tickets specs' selected rows use HighlightText. The dogfood reply text
  view no longer collapses.
- **`make check-gui`** adds Tests/View/appearance.sh, which renders every
  screen in light and dark and checks a bad fixture is caught.

## 0.1.0 (2026-11-16)

The first versioned release (private).

- **Engine (libTrellisEngine, Foundation only):**
  - CSS Flexbox and CSS Grid layout, with container queries.
  - Absolute positioning against the parent, physical and logical
    alignment keywords, `safe`/`unsafe` overflow alignment, and
    `aspect-ratio`.
  - Pixel-grid rounding.
  - Defaults: `border-box`, and `display: block` is a column flex container
    (see docs/agents.md section 4).
- **Grid:**
  - explicit and implicit tracks, including implicit tracks before the
    explicit grid;
  - `repeat()` with auto-fill/auto-fit, whose count also comes from
    min/max sizes;
  - `minmax()`, `fit-content()`, fr sizing (indefinite and min/max-bounded),
    and percentage tracks, gaps and margins;
  - named areas, auto-placement (sparse and `dense`), multi-size
    `grid-auto-rows/columns`;
  - the automatic minimum size of items;
  - abspos items in grid areas.
- **AppKit layer (libTrellis):**
  - TRBoxView, and the .trellis markup loader TRLoader (outlets by KVC,
    actions, templates, sample content);
  - view measurement, with the `TRSizeForWidth` hook for width-dependent
    views.
- **Tools:**
  - trellis-lint (markup, styles and owner bindings);
  - trellis-render (headless PNG and frame JSON with layout lint; window-free
    on macOS);
  - trellis-case (JSON conformance cases), trellis-bench, and the
    TrellisPreview app.
- **Builds:** GNUstep (gnustep-make; `make -j`, `make shared=no`,
  `make check`, `make check-gui`) and macOS (Makefile.macos, plain Apple
  clang).
- **Conformance at release, the same on Linux and macOS:**
  - Yoga gentest 906/906, WPT css-grid 1201/1201, and WPT css-flexbox
    827/838.
  - The 11 flexbox failures are the documented block-as-column divergence.
- **Known gaps:** no block or inline flow, no `calc()`, no named grid lines
  or subgrid, and abspos is relative to the parent box. See
  docs/known-issues.md.
