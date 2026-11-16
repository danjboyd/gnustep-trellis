# Dogfood: AIManager's ask detail in Trellis

A Trellis spec of AIManager's ask-detail view (`AIMAskDetailView
-layoutContent`), for review before any port. Nothing here touches the
AIManager repo; agent-lead does the port once the maintainer approves it.

| File | What it is |
|---|---|
| `AskDetail.trellis` | The proposal. |
| `before.trellis` | Today's fixed layout, approximated in Trellis for comparison. Not a proposal. |
| `AIMAskDetailOutlets.h` | The owner contract: the outlets and actions the view would expose. A stand-in, not AIManager's header. |
| `AskDetail.sample.json`, `before.sample.json` | Invented sample content (no real asks). |
| `frames/before-after-{340,520,900}.png` | Before (left) and after (right), Adwaita, 680 px tall. |
| `frames/*.json` | The frame dumps behind each render, with lint. |

## What changes, by retro item

The items are from fun-themes' Gumdrop assessment of AIManager (2026-11-13).

1. **Every label and decision readable.**
   - Today the body gets whatever height is left after about fifteen
     fixed-height controls, at least 70 px. At 340 × 680 that's three lines.
   - In the proposal, the header, body and thread scroll as one document,
     read at natural height. The thread no longer has its own nested
     scroller.
   - **The decision never scrolls away** (agent-lead's review: the maintainer
     answers asks back to back). It has its own panel: below the document
     at narrow widths, taking 2/5 of the height, and a 340 px column beside
     it at 760 px and wider.
   - The panel scrolls the pick, the other options, the reply box and the
     agent actions. Its bar is pinned (Do it, Send reply, Snooze, Dismiss,
     status), so Do it and Send reply are visible without scrolling at
     every size. The follow-up input stays pinned at the bottom.
   - Below 520 px only Do it and Send reply stay pinned, with the status
     under them. Snooze and Dismiss move into the panel's scroller, right
     after the reply box. (The status needs about 111 px and only about 78
     are left beside the buttons at 340, so it takes its own line.)
2. **Compact density coherent** (item 3).
   - No fixed control heights (today: 20, 24, 26, 30 and 32 pt rows, and
     a 64 pt reply box). Every control takes its theme's intrinsic size, and
     wrapped text is measured at its width.
   - So Compact density, or a user text size, reflows the view with no
     per-density constants.
3. **The workspace used deliberately** (item 5).
   - Sentence-case section labels instead of ALL CAPS.
   - Section labels use Adwaita's dim-label colour #5e5c64: 6.0:1 on the
     panel's #f6f5f4, where the old #77767b was 4.1:1, below the 4.5:1 that
     normal-size text needs.
   - All button rows wrap. Today the two action rows and the attachments
     row (fixed offsets w−172 / w−80) run off the right edge at 340.
   - The attachments row is hidden until something is attached, as in the
     app.
   - At 760 px and wider, the body and thread take all the width beside the
     decision column.

A slot is left under the body for the ask-terminal strip (aimanager
31e3717). It's `display: none` until the app has a terminal to show.

## Lint

| Width | Before | After |
|---|---|---|
| 340 | 10 findings: the link, attachments and both action rows overflow (Dismiss, the status and two agent buttons run off the right edge); the thread label clips | 0 |
| 520 | 5: the fixed 24/26/30 pt rows are shorter than Adwaita's 34 pt buttons | 0 |
| 900 | 5: as at 520 | 0 |

In the before frames, the actions, thread and part of the reply box are
clipped below the window at 340 × 680. In the proposal, Do it and Send reply
are always visible.

**Caveat:**
- `before.trellis` is reconstructed from agent-lead's description, not
  from the source.
- The follow-up input is pinned in both, and what doesn't fit above it in the
  before layout is clipped. The real view may clip a little differently.
- The point of the comparison is the squeezed body and the rows that don't
  wrap, not the exact overflow.

## Reproduce

```
. scripts/env.sh && make
trellis-lint dogfood/AskDetail.trellis --owner dogfood/AIMAskDetailOutlets.h
scripts/run-headless.sh obj/trellis-render dogfood/AskDetail.trellis \
  --sample dogfood/AskDetail.sample.json --widths 340,520,900 --height 680 \
  --theme Adwaita --png after.png --json after.json --lint
```

Renders run only under `scripts/run-headless.sh` (private Xvfb and
GNUSTEP_HOME). The Adwaita theme itself is unchanged.

## Notes for the port

- `body` and `thread` are labels here. In the app they're the existing
  NSTextView and thread view. Each sits in the flow at its natural height,
  not in its own scroller.
- `reply` is an NSTextView in a scroll view, at least 56 pt tall inside a
  bordered box.
- Snooze and Dismiss appear twice in the spec: in the bar from 520 px up,
  and in the panel's scroller below that. Only one pair is visible at a
  time; bind both to the same actions and state.
- The bar's Send reply is always shown here. The app can disable it while
  the reply box is empty.
- `links` and `optionButtons` hold stand-in buttons for the render. The app
  adds its own in code, and the rows wrap them.
