# Dogfood: AIManager's Tickets triage desk in Trellis

Layout specs for two pieces of AIManager's Tickets triage desk
(`AIMTriageDeskView`), which agent-tickets built on 2026-11-16 (its goal
#838). agent-tickets owns the code. These files are a layout check for
it, in the same format as the ask-detail spec in `dogfood/`. Nothing here
touches the AIManager repo.

| File | What it is |
|---|---|
| `Blocked.trellis` | Proposal: the Blocked rail section, and a card with a declined prerequisite and the B note field open. |
| `Batch.trellis` | Proposal: Intake batch dispatch with seven tickets, plus the hold text in the undo bar. |
| `before-Blocked.trellis`, `before-Batch.trellis` | Today's `-layout`, approximated from agent-tickets' description: fixed constants, nothing wraps, and anything that doesn't fit is clipped. |
| `AIMTriageDeskOutlets.h` | The owner contract (a stand-in, not AIManager's header). |
| `frames/{blocked,batch}-before-after-{340,520,900}.png` | Before (left) and after (right), Adwaita, 680 px tall. |
| `frames/*.json` | The frame dumps behind each render, with lint. |

## The proposal

Both states share one desk layout.

- **From 640 px up**, the rail is 270 px wide beside the card, as today.
- **Below 640 px**, the rail is hidden and a ☰ button in the pulse strip
  opens it. In the app it would open as an overlay. The card, the primary
  action and the undo bar get the width. (Today the card is at least
  200 px wide next to the 270 px rail, so at 340 the card and its buttons
  run off the right edge.)
- **The pulse strip** wraps. Below 640 px it keeps only ☰ and the urgent P1
  chip; the other counts are on the rail's section headers, behind ☰.
- **The card scrolls**, blocker list and batch list included. The note
  field, the action bar and the undo bar never scroll away. The composer
  shrinks to 56 pt below 640 px.
- **There are no fixed control heights**, so nothing depends on 24, 30, 34 or
  150 pt constants, and Compact density reflows the desk.
- **The action bar wraps.** At 340 the three Blocked buttons stack, with
  "Still blocked ⏎" first.
- **Rail section headers** are quiet and in sentence case, as on the ask
  screen.

### Blocked

- The blocker list stays attributed text in the card, as you built it. A
  declined prerequisite is in the warning colour. Editing stays with B and
  the note field.
- "Still blocked ⏎" is the default button. Keep stays a button, which
  reads well.

### Intake batch dispatch

- **Batch members are marked in the rail**, with a ✓ before the title and a
  light tint, and the Intake group header says "7 in batch". Below 640 px,
  the ☰ button reads "☰ Rail · 7 in batch". You'd asked for this as a
  finding.
- The batch list scrolls inside the card, and the action bar and undo bar
  stay fixed at every width.

## Findings for the app

1. **"Dispatch n to their suggested agents ⏎" doesn't fit below about
   380 px.** It's 364 pt wide under Adwaita, and 316 pt are available at
   340. The spec shows "Dispatch 5 ⏎" below 640 px, using two buttons, one
   per width range; the app can just change the title.
2. **The Undo button is 3 pt too narrow.** "Undo (Ctrl+Z)" needs 153 pt
   under Adwaita, and the fixed width is 150. Size it to fit its title.
3. **The 18 pt hint line can't hold the hint at narrow widths.** At 340 the
   hint needs four lines (72 pt). Let it wrap.
4. **The hold text is long.** At 340 it wraps to four lines, even with the
   full width. Consider "Dispatch 5 · goes in 10 s" at narrow widths, with
   the list in a tooltip or in the card.
5. **Rail titles: wrap or truncate?** The proposal wraps them, so nothing is
   hidden, but that fits fewer rows. Today's one-line titles (see the before
   frames) let you scan more tickets. For a triage rail, truncating with the
   full title in the card is probably the better trade. It's your call;
   either works in this layout.
6. **Both batch dispatch buttons are marked default** in the spec, since
   only one is visible at a time. AppKit ignores hidden buttons for key
   equivalents, so ⏎ is unambiguous.

## Lint

Both proposals lint clean: 0 findings at 340, 520
and 900.

The before counts (Blocked 19/19/15, Batch 24/24/22) are **inflated by my
approximation and shouldn't be quoted as evidence**: the app's pulse strip
uses borderless buttons, and I used bezelled ones in its 24 pt strip. The
real problems among them are findings 1–3, plus the card and action bar
being clipped at 340.

## Reproduce

```
. scripts/env.sh && make
trellis-lint dogfood/tickets/Blocked.trellis --owner dogfood/tickets/AIMTriageDeskOutlets.h
scripts/run-headless.sh obj/trellis-render dogfood/tickets/Blocked.trellis \
  --widths 340,520,900 --height 680 --theme Adwaita --png blocked.png --lint
```

Renders run only under `scripts/run-headless.sh` (private Xvfb and
GNUSTEP_HOME). The Adwaita theme itself is unchanged.
