# Dogfood: AIManager's Work tab in Trellis

A layout spec for AIManager's Work tab: the wall of agent tiles
(`AIMWallView`), the agent detail panel (`AIMAgentDetailView`), and the
new "Focus today" strip from the approved mockup (board 3). It's for review
before the port, in the same format as the ask-detail spec in `dogfood/`.
Nothing here touches the AIManager repo. **All data is made up** (agent-a,
build-bot, Project Alpha, host-1, ...).

| File | What it is |
|---|---|
| `Work.trellis` | The proposal. |
| `before-Work.trellis` | Today's layout, approximated from the app developer's description: a fixed split, 110 px tiles, hand-placed detail controls. |
| `AIMWorkOutlets.h` | The owner contract (a stand-in, not AIManager's header). |
| `frames/before-after-{340,520,900}.png` | Before (left) and after (right), Adwaita light, 680 px tall. |
| `frames/light-dark-{340,520,900,1440}.png` | The proposal under Adwaita light (left) and dark (right). 1440 shows the four-card Focus row and five tile columns, as in the mockup. |
| `frames/*.json` | The frame dumps behind each render, with lint. |

## The proposal

- **Focus today** sits at the top of the wall and scrolls with it. It has
  a header ("Focus today", the "kept from Friday" note, and Change…), then
  the cards. Each card shows the project and ★, the initiative (bold), a
  stage chip ("Build" on AccentColor, or "Needs you" on Mark with a 2 px
  Mark border on the card), and one line of what's happening.
  - **Four cards in a row when the wall is 760 px or wider, two from
    400 px, one below that.** These breakpoints test the *wall's* width,
    not the window's, so the strip narrows correctly when the detail panel
    sits beside it. At a 900 px window, the wall is 580 px wide and shows
    two columns. Four columns need a window of about 1100 px with the
    panel open (see the 1440 frame).
- **The wall** keeps today's grid: tiles at least 230 px wide that stretch
  to fill (`repeat(auto-fill, minmax(230px, 1fr))`, gap 10, padding 12).
  The tile anatomy is unchanged: the state bar, the name and account pill,
  the status and "host · harness", badges, the headline and the last line
  (manager note, today's goal progress, or purpose). What changes:
  - **tiles grow to fit their text** (at least 110 px) instead of
    clipping, so the headline and status wrap and nothing is cut off;
  - **group headers are sentence case:** "Needs you (1)", as on the ask
    screen.
- **The detail panel** is a 320 px column beside the wall from 760 px up.
  Below that it moves under the wall, taking 45% of the height. Both
  scroll on their own, and its button rows wrap, so Retire never falls
  off the edge.
- **Colours are all system colours,** and both appearances lint clean.
  The state bars use Mark (needs you), AccentColor (working), GrayText
  (idle) and -tr-error (stopped); selection is a 2 px AccentColor border.
- **Selection and keyboard behaviour** stay in the app's code. The spec
  marks agent-a's tile `selected` to show the style.

## Findings for the app

1. **Below 760 px the wall gets crowded.** The Focus strip and the
   detail panel (45% of the height) leave little room for tiles at 520 and
   340. Options, in my order of preference:
   (a) show the detail panel only when a tile is selected, and close it
       with Esc;
   (b) collapse the Focus strip to its header line below 520, with ▸ to
       expand;
   (c) make the detail a sheet over the wall at narrow widths.
   The spec shows the plain stacked version, so you can judge it.
2. **The account pill and the "Needs you" chip use Mark** (Adwaita's
   yellow highlight), with MarkText on top. Trellis 0.2.0 drew MarkText in
   the normal text colour, which in dark is near-white on yellow. This
   spec found that, and it's fixed on main right after the tag: MarkText
   is now always black. If you'd rather avoid the bright yellow, use
   AccentColor with AccentColorText for the pill instead.
3. **There's no monospace font in Trellis CSS yet,** so the Screen capture
   is a plain NSTextView here. Set its font in code, as today.
4. **The Goals text in the detail panel** is one wrapping paragraph. If
   you want purpose, project goal and today's goal on separate lines,
   make them three `text` elements.
5. **The "Change…" button and the Focus note** wrap under the title at
   narrow widths, so nothing clips.

## Lint

- **The proposal lints clean** (0 findings) at 340, 520, 900 and 1440, in
  both Adwaita light and dark, including `low-contrast`. trellis-lint
  with the owner header reports 0 errors.
- **The before approximation** has 42 findings at 340 (17 clipped-text,
  20 overflow, 4 collapsed, 1 offscreen), 31 at 520 and 22 at 900. It
  approximates the hand-drawn tiles with one-line labels in 110 px boxes,
  so its counts are illustrative, not evidence. The real problems are
  the clipped tile text and the button row running off the panel.

## Reproduce

```
. scripts/env.sh && make
trellis-lint dogfood/work/Work.trellis --owner dogfood/work/AIMWorkOutlets.h
scripts/run-headless.sh obj/trellis-render dogfood/work/Work.trellis \
  --widths 340,520,900,1440 --height 680 --theme Adwaita --png work.png --lint
scripts/run-headless.sh obj/trellis-render dogfood/work/Work.trellis \
  --widths 340,520,900,1440 --height 680 --theme Adwaita --appearance dark --lint
```

Renders run only under `scripts/run-headless.sh` (a private Xvfb and
GNUSTEP_HOME).
