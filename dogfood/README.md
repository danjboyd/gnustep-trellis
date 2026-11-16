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
   - In the proposal, everything above the follow-up input scrolls as one
     document. The body and the thread are read at their natural height,
     and the follow-up input stays pinned and reachable.
   - The thread no longer has its own nested scroller.
2. **Compact density coherent** (item 3).
   - No fixed control heights (today: 20, 24, 26, 30 and 32 pt rows, and
     a 64 pt reply box). Every control takes its theme's intrinsic size, and
     wrapped text is measured at its width.
   - So Compact density, or a user text size, reflows the view with no
     per-density constants.
3. **The workspace used deliberately** (item 5).
   - Sentence-case section labels instead of ALL CAPS.
   - All button rows wrap. Today the two action rows and the attachments
     row (fixed offsets w−172 / w−80) run off the right edge at 340.
   - At 760 px and wider, the decision (pick, options, reply, actions) moves
     into a 300 px side column. The body and thread take the freed width.
   - At narrow widths the order stays the app's: header, body, decision,
     thread.

A slot is left under the body for the ask-terminal strip (aimanager
31e3717). It's `display: none` until the app has a terminal to show.

## Lint

| Width | Before | After |
|---|---|---|
| 340 | 29 findings: rows overflow the right edge; actions, thread and follow-up fall below the window | 0 |
| 520 | 11 | 0 |
| 900 | 11 | 0 |

**Caveat:**
- `before.trellis` is reconstructed from agent-lead's description, not
  from the source.
- In particular, when the content is taller than the window, the real view
  keeps the follow-up input pinned and clips differently. The before frames
  instead push it off the bottom.
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
- `links` and `optionButtons` hold stand-in buttons for the render. The app
  adds its own in code, and the rows wrap them.
