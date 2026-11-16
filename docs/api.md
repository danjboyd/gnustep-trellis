# Trellis public API (v0.1)

This page lists what Trellis 0.1 promises to keep. Anything here changes
only with a version bump and a CHANGELOG entry; anything not listed is
internal and may change without notice.

Headers install under `Trellis/`. Import `<Trellis/TrellisEngine.h>` for
the layout engine (Foundation only), and `TRBoxView.h`, `TRLoader.h` and
`TRViewMeasure.h` for the AppKit layer.

## The .trellis format

The markup and CSS described in [agents.md](agents.md), sections 2 to 4,
are public: element names, attributes (`id`, `class`, `action`,
`no-outlet`, `default`, `wraps`, `placeholder`, `items`, `type`, ...), the
`<!-- owner: Class -->` comment, `<style>` with the listed properties,
selectors and `@container` queries, and the `Screen.sample.json`
convention. Unknown properties and bad values stay errors.

Colours: hex, `rgb()`/`rgba()`, a few names, and the CSS system colours
(`Canvas`, `CanvasText`, `Field`, `FieldText`, `ButtonFace`, `ButtonText`,
`ButtonBorder`, `GrayText`, `Highlight`, `HighlightText`, `SelectedItem`,
`SelectedItemText`, `AccentColor`, `AccentColorText`, `LinkText`, `Mark`,
`MarkText`), plus `-tr-window-background`, `-tr-separator`,
`-tr-secondary-text` and `-tr-error`. System colours resolve to AppKit's
dynamic colours when the view draws, so they follow the appearance and
theme (since 0.1.1).

## AppKit layer (libTrellis)

| API | Header | What it is |
|---|---|---|
| `+[TRLoader loadFile:owner:error:]`, `+loadDocument:owner:error:` | TRLoader.h | Build a view tree from a .trellis file, binding outlets by `id` (KVC: properties or ivars, `_name` included) and actions by `action=`. |
| `+[TRLoader instantiateTemplate:...]`, `+applySample:toView:error:`, `+viewWithIdentifier:inView:` | TRLoader.h | Templates, sample content, lookup by id. |
| `TRBoxView`: `+boxWithStyle:`, `-initWithStyle:`, `style`, `-setStyleDeclarations:`, `-addSubview:style:`, `-setStyleDeclarations:forSubview:`, `-nodeForSubview:`, `-addConditionalStyle:when:`, `-invalidateSubview:`, `-layoutTrellis`, `-rootBox`, `node` | TRBoxView.h | A view whose subviews Trellis lays out. Plain `-addSubview:` works too (intrinsic size). |
| `TRScrollBox` (`contentBox`) | TRLoader.h | The view `<scroll>` creates. |
| `TRSizeForWidth` protocol: `-trellisSizeForWidth:` | TRViewMeasure.h | Opt-in height-for-width measuring for custom views (CGFLOAT_MAX = max-content). |
| `TRMeasureView`, `TRBaselineOfView` | TRViewMeasure.h | How Trellis measures a leaf view; usable from custom measure blocks. |
| `TRColorFromCSS` | TRBoxView.h | CSS colour string to NSColor. |

## Engine (libTrellisEngine, Foundation only)

| API | Header | What it is |
|---|---|---|
| `TRNode`: construction (`+node`, `+nodeWithStyle:`), tree (`children`, `parent`, `-addChild:`, `-insertChild:atIndex:`, `-removeChild:`, `-removeAllChildren`), `style`, `identifier`, `context`, `measureBlock`, `baselineBlock`, `-markDirty`, `dirty` | TRNode.h | A layout box. |
| Layout: `-layoutWithAvailableSize:`, `-layoutWithAvailableSize:direction:`, `pixelScale`, `layoutFrame`, `layoutDirection`, `contentSize`, `-layoutPaddingForEdge:`, `-layoutBorderForEdge:`, `-layoutMarginForEdge:`, `-absoluteFrame`, `-layoutBaseline`, `hasOverflow`, `-frameDump` | TRNode.h | Running layout and reading results. Frames are border boxes relative to the parent's border box. |
| Container queries: `-addConditionalStyle:when:error:`, `matchedConditions` | TRNode.h | `@container`-style conditional declarations. |
| `TRStyle`: `+style`, `+styleWithDeclarations:[error:]`, `+styleWithDictionary:error:`, `-applyDeclarations:error:`, `-applyDictionary:error:`, `-setValue:forProperty:error:`, the typed properties, the per-edge accessors, `-declarationString`, `otherDeclarations` | TRStyle.h | Layout properties by CSS name or typed. |
| `TRTypes.h`: `TRValue`, `TRSize`, `TRRect`, `TRPoint`, `TREdge`, `TRMeasureMode`, the enums (`TRDisplay`, `TRAlign`, ...), `TRPx`, `TRAutoValue`, `TRNoneValue`, `TRUndefined` | TRTypes.h | Value types. New enum members may be added at the end. |
| `TRMarkupDocument`, `TRMarkupElement`, `TRMatchedDeclarations` | TRMarkup.h | Parsed .trellis documents (read-only). |
| `TRLintFrameTree` | TRLint.h | Lint a frame dump (what trellis-render --lint and TrellisPreview use). |
| `TRStyleErrorDomain`, `TRMarkupErrorDomain` | | Error domains. Error codes and messages may change; `file:line:col` stays in the message. |

## Tools

`trellis-lint`, `trellis-render` (`--widths`, `--height`, `--theme`,
`--sample`, `--png`, `--json`, `--lint`, and since 0.1.1 `--appearance
light|dark` and `-DefaultsKey value` pass-through), `trellis-case` and
TrellisPreview are supported, with their documented options.

The frame-dump JSON keys `x`, `y`, `width`, `height`, `class`, `id`,
`children`, `intrinsic` and `lint` are stable. Since 0.1.1 the dump also
carries the resolved colours `background`, `textColor` and
`windowBackground`. Other keys may be added.

## Internal (not part of the API)

- `TRStyleStorage` and `TRStyleStorageInitial()` in TRStyle.h: the
  storage layout changes between versions. Use TRStyle's properties.
- `TRNode+Internal.h`, `TRGrid.h`, and everything in `Source/Engine/*.m`
  not declared in an installed header.
- `TRCellSize` and `TRContentSignature` in TRViewMeasure.h.
- The layout cache, rounding details below one pixel, and lint wording.
