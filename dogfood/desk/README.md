# Dogfood: AIManager's triage desk shell and cards (G3–G7)

A layout spec for the next step of AIManager's Tickets triage desk
(`AIMTriageDeskView`), from the four approved mockups. The app's
developer owns the code; this is a layout check for the port, in the same
format as `dogfood/tickets` (Blocked, Batch). Nothing here touches the
AIManager repo. **All data is made up** (Maria Lopez, Sam Ortiz,
agent-data, #482, ...).

| File | What it is |
|---|---|
| `Intake.trellis` | The shell (G3, G6), the card header (G4), the Intake body (G7) and the reply-draft card (G5). Mockup 1. |
| `Plan.trellis` | A hotfix at the Plan gate. Mockup 2, drawer closed. |
| `Plan-drawer.trellis` | The same, with the drawer open on Agent chat. Mockup 2. |
| `Verify.trellis` | The Verify gate, with the undo bar showing a held approval. Mockup 3. |
| `Project.trellis` | A project with work items and prerequisites. Mockup 4. |
| `AIMDeskOutlets.h` | The owner contract (a stand-in, not AIManager's header). |
| `gen-cards.py` | Builds Plan, Verify, Project and Plan-drawer from Intake's shell (marked regions), so the shell stays in one place. |
| `frames/<card>-{340-520,900,1440}-light-dark.png` | Adwaita light and dark, 900 px tall. The 340-520 strip is 340 light, 340 dark, 520 light, 520 dark. |
| `frames/plan-drawer-*.png` | The drawer at 1440 (light) and 900 (dark), and at 340 (light) and 520 (dark). |

All five files lint clean (0 findings) at 340, 520, 900 and 1440 in
both Adwaita light and dark, and `trellis-lint --owner AIMDeskOutlets.h`
reports 0 errors and 0 warnings.

## The shell

- **Top bar:** dark in both appearances (a fixed pair: #1c1d1f with
  light text). "Helpdesk", then the pulse chips (AIMDeskPulseParts,
  Mine first): flat filter buttons (`bordered="no"`, Trellis 0.3), the
  active one white and bold, the hotfix count as a tinted chip, and on
  the right Oldest wait and Unheard. It wraps. Below 640 px it
  keeps ☰ Rail, Mine and the hotfix chip; the other counts are on the
  rail's section rows.
- **Rail:** 260 px from 640 px up, behind ☰ below that. "Your move · 5"
  by group (Hotfix in the error colour), with two-line rows: the title
  wraps, and the meta line carries words ("draft unsent", "New reply").
  The other sections are folded to one line with a count. The selected
  row is Highlight.
- **Card:** a Canvas card, 920 px at most and centred, with a 1 px
  separator border and 8 px corners. The card and the reply card scroll;
  the top bar, the rail filter, the decision bar and the undo bar don't.
  - **Header (G4):** the gate line ("INTAKE: IS THIS A GOOD TICKET?",
    then #, area and age; a Hotfix tag in front on hotfixes), the title,
    the requester, and the last-heard chip: the warning tint
    (`-tr-warning-background`, Trellis 0.3) when the requester has heard
    nothing, a quiet chip otherwise.
  - **Body:** per gate (below).
  - **The decision bar** (`#decision`) is pinned under the scroller,
    the same width as the card: the note field (N), then the action bar
    (AIMDeskAction buttons, title · key, the primary one the default
    button). It wraps, and the hint ("Shift+Return dispatches without
    sending") goes right, or under the buttons below 640 px. So the
    primary action and Undo are always on screen.
- **Reply draft (G5):** its own card under the decision: "Reply to … ·
  Draft: <kind> · visible to requester", "E to edit", the body, and
  "Send only · Cmd+Return" and "Redraft · Cmd+R".
- **Undo bar:** under everything, hidden until an action is held
  (Verify shows it). Below 640 px the text takes the full width and the
  button goes under it.
- **Drawer:** closed by default. Open (Plan-drawer), it's a 360 px column
  beside the card from 1100 px up; below that it takes the card column's
  place, and Escape returns to the card, so neither gets squeezed.

## The cards

- **Intake:** restatement; quality checks in two columns (one below
  640 px) with the Flag line in the error colour; the original ticket in
  a quiet panel with its attachments; Assignee (radios "1 agent-data",
  "2 agent-web", ...) with the suggestion under it, and Track (Standard,
  Hotfix, Project).
- **Plan:** diagnosis with its confidence and evidence line, the proposed
  steps, the blast radius as a three-column panel on the warning tint
  (one column below 640 px), and Alternatives and Evidence as expander rows (▸ button on the
  left, "2 · Space to expand" on the right).
- **Verify:** the Done/Changed step table, with the deviation row on
  the warning tint; Proof and Live status in two columns (stacked below 640 px); and
  Change detail as an expander.
- **Project:** "3 of 7 work items done" with the counts, a seven-segment
  bar (done CanvasText, needs-you AccentColor, fixing GrayText, open
  separator), and the work-item table (state, item, agent, depends on).
  The needs-you row is Highlight and bold, done rows are GrayText. Below
  760 px each row takes two lines: state and item, then agent and
  dependencies.

## Findings for the app

1. **The primary titles don't fit at 340.** "Dispatch and send
   acknowledgment · Return" is 410 px wide under Adwaita, and the card has
   about 300. The spec swaps in a short title below 640 px ("Dispatch and
   send · Return", "Approve and send · Return", "Confirm and close ·
   Return", "Open #502 · Return") as two buttons, one per width range.
   In the app, a `shortTitle` on AIMDeskAction would do it.
2. **Soft tints: done in Trellis 0.3.** `-tr-warning-background` with
   `-tr-warning-text` is the mockup's peach and brown, a fixed light pair
   like Mark. The spec uses it for "heard nothing", the blast radius and
   the Changed rows; "needs you" stays Highlight.
3. **No segmented control or tab strip yet.** The drawer's tabs are a
   pop-up here (six bezel buttons wrapped to three rows at 360 px).
   Assignee and Track are radio groups, so the selection is the
   control's own state. The number and H/P keys pick them in code.
4. **Flat chips: done in Trellis 0.3.** `<button bordered="no">` with
   `color:`. Its cell draws the title itself, because the Adwaita theme
   draws push-button titles in its own colour. If you set a chip's title
   in code, set `attributedTitle` with the colour, since `-setTitle:`
   drops it.
5. **The gate line is written in capitals,** and section labels are
   small bold GrayText in sentence case. Trellis has no `text-transform`
   or `letter-spacing`, and sentence case matches the ask screen.
6. **One default button at a time.** With the drawer open, Return
   belongs to "Send to agent", so the card's primary drops its key
   equivalent while the chat field has focus (the spec shows that state).
7. **Expanders:** the ▸ rows are buttons; the app inserts the expanded
   content under the row and flips the arrow.
8. **The decision bar is pinned** (done, as you asked). At 340 it takes
   about a quarter of the height (Intake: four rows of buttons with the
   spec's short titles); shorter `shortTitle`s ("Dispatch", ...) and
   hiding the hint below 640 px would win some of that back.

## Reproduce

```
. scripts/env.sh && make
trellis-lint dogfood/desk/Intake.trellis --owner dogfood/desk/AIMDeskOutlets.h
scripts/run-headless.sh obj/trellis-render dogfood/desk/Intake.trellis \
  --widths 340,520,900,1440 --height 900 --theme Adwaita --png intake.png --lint
scripts/run-headless.sh obj/trellis-render dogfood/desk/Intake.trellis \
  --widths 340,520,900,1440 --height 900 --theme Adwaita --appearance dark --lint
```

After editing the shell in Intake.trellis, run `python3 -I gen-cards.py`
here to regenerate the other four. Renders run only under
`scripts/run-headless.sh` (a private Xvfb and GNUSTEP_HOME).

## Also found

Building this spec found and fixed one Trellis engine bug (1ece127, in
v0.2.3): an
item with `width: 100%; max-width: 920px` in a column had its height
measured at the unclamped width, so the wrapped action bar overflowed the
card. It also found a trellis-lint false positive for declarations that
start on a new line (475fc00, in v0.2.2). Port against Trellis v0.3.0 or
later: the spec uses its warning colours and flat buttons.
