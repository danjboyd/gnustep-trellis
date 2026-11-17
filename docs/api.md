# Trellis public API (v0.4)

This page lists what Trellis 0.4 promises to keep. Anything here changes
only with a version bump and a CHANGELOG entry; anything not listed is
internal and may change without notice.

Headers install under `Trellis/`. Import `<Trellis/TrellisEngine.h>` for
the layout engine (Foundation only), and `TRBoxView.h`, `TRLoader.h`,
`TRVirtualBox.h` and `TRViewMeasure.h` for the AppKit layer.

## The .trellis format

The markup and CSS described in [agents.md](agents.md), sections 2 to 4,
are public: element names, attributes (`id`, `class`, `action`,
`no-outlet`, `default`, `wraps`, `placeholder`, `tabindex`, `a11y-label`,
`label-for`, `role` (`group`, `none`), `items`, `type`, ...), the
`<!-- owner: Class -->` comment, `<style>` with the listed properties,
selectors and `@container` queries, and the `Screen.sample.json`
convention. Unknown properties and bad values stay errors.

Colours: hex, `rgb()`/`rgba()`, a few names, and the CSS system colours
(`Canvas`, `CanvasText`, `Field`, `FieldText`, `ButtonFace`, `ButtonText`,
`ButtonBorder`, `GrayText`, `Highlight`, `HighlightText`, `SelectedItem`,
`SelectedItemText`, `AccentColor`, `AccentColorText`, `LinkText`, `Mark`,
`MarkText`), plus `-tr-window-background`, `-tr-separator`,
`-tr-secondary-text` and `-tr-error`, and since 0.3 `-tr-warning-background`
and `-tr-warning-text` (a fixed light pair, like `Mark`/`MarkText`). System
colours resolve to AppKit's dynamic colours when the view draws, so they
follow the appearance and theme (since 0.1.1).

Since 0.3, `<button bordered="no">` makes a flat, title-only button, and
`color:` on a button colours its title.

Since 0.4, `<virtual>` builds a virtualized list or grid (a
`TRVirtualBox`): attributes `layout` (`list`, `grid`), `template`,
`estimated-size` and `overscan`, and `<template id>` children. The
element's `padding`, gaps and `grid-template-columns` lay out the items;
a template whose root has `grid-column: 1 / -1` takes a whole row. In a
sample file, a virtual box's id takes `{"items": [...], "repeat": n}`,
where an entry `{"_repeat": n, "items": [...]}` is a run, `"_template"`
picks the template, and `{i}`, `{n}` and `{n:W}` number the items;
`"scroll-to": index` scrolls there. Ids repeat freely across templates.

Since 0.4, custom properties: `--name: value` declarations
that inherit down the element tree, `var(--name[, fallback])` in any
value, and the built-in `--tr-*` tokens listed in agents.md section 3
(names and meanings are API; their values follow the theme).

## AppKit layer (libTrellis)

| API | Header | What it is |
|---|---|---|
| `+[TRLoader loadFile:owner:error:]`, `+loadDocument:owner:error:` | TRLoader.h | Build a view tree from a .trellis file, binding outlets by `id` (KVC: properties or ivars, `_name` included) and actions by `action=`. |
| `+[TRLoader instantiateTemplate:...]`, `+applySample:toView:error:`, `+viewWithIdentifier:inView:` | TRLoader.h | Templates, sample content, lookup by id. |
| `TRBoxView`: `+boxWithStyle:`, `-initWithStyle:`, `style`, `-setStyleDeclarations:`, `-addSubview:style:`, `-setStyleDeclarations:forSubview:`, `-nodeForSubview:`, `-addConditionalStyle:when:`, `-invalidateSubview:`, `-layoutTrellis`, `-rootBox`, `node`; since 0.2 `managesKeyViewLoop`, `-recalculateTrellisKeyViewLoop`, `firstKeyView`; since 0.4 `-heightForWidth:` | TRBoxView.h | A view whose subviews Trellis lays out. Plain `-addSubview:` works too (intrinsic size). |
| `TRScrollBox` (`contentBox`) | TRLoader.h | The view `<scroll>` creates. |
| `TRVirtualBox` (since 0.4): `-initWithMode:`, `mode`, `virtualLayout`, `dataSource`, `-setContainerDeclarations:error:`, `estimatedSize`, `overscan`, `defaultTemplate`, `-registerTemplate:ofDocument:error:`, `-registerTemplateElement:ofDocument:`, `-registerViewFactory:forKind:`, `-reloadData`, `-insertItemsAtIndexes:`, `-removeItemsAtIndexes:`, `-moveItemAtIndex:toIndex:`, `-reloadItemsAtIndexes:`, `-scrollToItemAtIndex:position:`, `-focusItemAtIndex:last:`, `-viewForItemAtIndex:`, `-indexOfItemView:`, `realizedIndexes`, `pooledViewCount`, `visibleItemViews`, `visibleRange`, `-updateVirtualContent`; `TRVirtualDataSource`; `TRVirtualScrollPosition` | TRVirtualBox.h | The view `<virtual>` creates: views only for the items on screen, reused per template, with scroll anchoring, keyboard focus across the edge, and list/grid accessibility. |
| `+[TRLoader instantiateTemplateElement:ofDocument:error:]` (since 0.4) | TRLoader.h | A copy of a `<template>` element (top-level or inside `<virtual>`). |
| `TRFlatButtonCell` (since 0.3) | TRLoader.h | The cell of `<button bordered="no">`: draws its attributed title itself, so its colour shows under any theme. |
| Hot reload (since 0.2): `+[TRLoader setHotReloadEnabled:]`, `+hotReloadEnabled`, `+reloadChangedFiles`, `-trellisDidReload:` (owner, optional), `TRLoaderDidReloadNotification`, `TRELLIS_HOT_RELOAD` / `TRHotReload` | TRLoader.h | Development only: rebuilds boxes loaded from files when the files change. |
| `TRSizeForWidth` protocol: `-trellisSizeForWidth:` | TRViewMeasure.h | Opt-in height-for-width measuring for custom views (CGFLOAT_MAX = max-content). |
| `TRMeasureView`, `TRBaselineOfView` | TRViewMeasure.h | How Trellis measures a leaf view; usable from custom measure blocks. |
| `TRColorFromCSS` | TRBoxView.h | CSS colour string to NSColor. |
| `TRUpdateThemeTokens` (since 0.4) | TRLoader.h | Sets the built-in tokens' metrics from the running theme (loading a document does it). |
| `TRApplyLeafStyle` (since 0.4) | TRBoxView.h | Text and colour declarations on a control outside any box. |
| `TRKeyViewProvider` protocol (since 0.4): `-trellisKeyViewSubtrees` | TRBoxView.h | A view that supplies its focusable subtrees in order to the managed key-view loop. |
| `TRSetTabIndex`, `TRTabIndex` (since 0.2) | TRBoxView.h | A view's tab index (markup `tabindex`). |
| `TRSetAccessibilityLabel`/`TRAccessibilityLabel`, `TRSetAccessibilityTitleView`/`TRAccessibilityTitleView`, `TRSetAccessibilityRole`/`TRAccessibilityRole` (since 0.2); `TRSetAccessibilityCollection`/`TRAccessibilityCollection`, `TRSetAccessibilityPosition`/`TRAccessibilityPosition` (since 0.4) | TRBoxView.h | Accessibility name, label link, role, and collection count and item positions; also pushed to NSAccessibility on Cocoa. |

## Engine (libTrellisEngine, Foundation only)

| API | Header | What it is |
|---|---|---|
| `TRNode`: construction (`+node`, `+nodeWithStyle:`), tree (`children`, `parent`, `-addChild:`, `-insertChild:atIndex:`, `-removeChild:`, `-removeAllChildren`), `style`, `identifier`, `context`, `measureBlock`, `baselineBlock`, `-markDirty`, `dirty` | TRNode.h | A layout box. |
| Layout: `-layoutWithAvailableSize:`, `-layoutWithAvailableSize:direction:`, `pixelScale`, `layoutFrame`, `layoutDirection`, `contentSize`, `-layoutPaddingForEdge:`, `-layoutBorderForEdge:`, `-layoutMarginForEdge:`, `-absoluteFrame`, `-layoutBaseline`, `hasOverflow`, `-frameDump` | TRNode.h | Running layout and reading results. Frames are border boxes relative to the parent's border box. |
| Container queries: `-addConditionalStyle:when:error:`, `matchedConditions` | TRNode.h | `@container`-style conditional declarations. |
| `TRStyle`: `+style`, `+styleWithDeclarations:[error:]`, `+styleWithDictionary:error:`, `-applyDeclarations:error:`, `-applyDictionary:error:`, `-setValue:forProperty:error:`, the typed properties, the per-edge accessors, `-declarationString`, `otherDeclarations` | TRStyle.h | Layout properties by CSS name or typed. |
| `TRTypes.h`: `TRValue`, `TRSize`, `TRRect`, `TRPoint`, `TREdge`, `TRMeasureMode`, the enums (`TRDisplay`, `TRAlign`, ...), `TRPx`, `TRAutoValue`, `TRNoneValue`, `TRUndefined` | TRTypes.h | Value types. New enum members may be added at the end. |
| `TRMarkupDocument`, `TRMarkupElement`, `TRMatchedDeclarations` | TRMarkup.h | Parsed .trellis documents (read-only). Since 0.4: `-customPropertiesForElement:`, `+setBuiltinCustomProperties:`, `+builtinCustomProperties`, `+defaultBuiltinCustomProperties`; `-declarationsForElement:` returns resolved declarations. |
| `TRVirtualLayout` (since 0.4): `-initWithMode:`, `mode`, `-setContainerDeclarations:error:`, `width`, `itemCount`, `estimatedSize`, `spansFullRow`, `estimateForItem`, `-setMeasuredHeight:forItem:`, `-isMeasured:`, `-forgetMeasuredHeights`, `-insertItemsAtIndex:count:`, `-removeItemsAtIndex:count:`, `contentHeight`, `columnCount`, `-frameForItem:`, `-widthForItem:`, `-heightForItem:`, `-rowForItem:column:`, `-itemsForViewportOffset:height:overscan:`, the anchor methods; `TRVirtualMode`, `TRVirtualAnchor` | TRVirtualLayout.h | The window engine behind `<virtual>`: item heights only, no views. |
| `TRLintFrameTree` | TRLint.h | Lint a frame dump (what trellis-render --lint and TrellisPreview use). |
| `TRStyleErrorDomain`, `TRMarkupErrorDomain` | | Error domains. Error codes and messages may change; `file:line:col` stays in the message. |

## Tools

`trellis-lint`, `trellis-render` (`--widths`, `--height`, `--theme`,
`--sample`, `--png`, `--json`, `--lint`, and since 0.1.1 `--appearance
light|dark` and `-DefaultsKey value` pass-through), `trellis-case` and
TrellisPreview are supported, with their documented options.
`trellis-bench` (since 0.4 with `--virtual N`) is a measuring tool; its
output format may change.

The frame-dump JSON keys `x`, `y`, `width`, `height`, `class`, `id`,
`children`, `intrinsic` and `lint` are stable. Since 0.1.1 the dump also
carries the resolved colours `background`, `textColor` and
`windowBackground`, and since 0.4 a virtual box's `virtual` (count,
columns, content height) with its visible items as `children` (each with
its `item` index, `y` relative to the viewport). Other keys may be added.

## Internal (not part of the API)

- `TRStyleStorage` and `TRStyleStorageInitial()` in TRStyle.h: the
  storage layout changes between versions. Use TRStyle's properties.
- `TRNode+Internal.h`, `TRGrid.h`, and everything in `Source/Engine/*.m`
  not declared in an installed header.
- `TRCellSize` and `TRContentSignature` in TRViewMeasure.h.
- `-[TRNode containerQueryParent]` (set by the view layer for scrolled
  content and virtual items).
- The layout cache, rounding details below one pixel, and lint wording.
