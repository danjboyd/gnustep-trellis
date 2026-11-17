# Moving a screen from 0.8 to 0.9

Five layout results changed in 0.9, each closer to the browser. For
earlier changes, see [migration-0.8.md](migration-0.8.md) and
[migration-0.7.md](migration-0.7.md).

| What changed | 0.8 | 0.9 |
|---|---|---|
| An **abspos root** without both left and right takes its fit-content width, and without both top and bottom its content height. With both insets it fills the space less the insets. | always the available size | shrinks to fit |
| A **grid whose width is only bounded** (for example in an `align-items: flex-start` column) sizes its auto columns to their content. | auto columns stretched across the space | content width; they stretch once the grid has its final width |
| A **root with `aspect-ratio`** and an auto width that fills the available width takes its height from the ratio, but never less than its content height. | content height | width / ratio, at least the content |
| **`baseline` / `last baseline` alignment in a column**: the items form a baseline group synthesized from their border boxes' start (end) edges, so they line up past the largest margin. | acted as flex-start | baseline group |
| An **abspos box inside static boxes whose containing block is a grid** is placed in its own grid area (grid-row / grid-column), and `bottom` uses the grid's final height. | the grid's padding box, and its height before min-height | its grid area, and the final height |

Also fixed, with no effect on existing frames unless you use them: the
size keywords' `min-content` for flex rows follows css-flexbox 9.9.1, and
`max-content` is never below `min-content`.

**What to check in a screen:**
- An abspos box laid out as a root (a view's root node with `position: absolute`).
- A `display: grid` box that isn't stretched by its parent and has auto columns.
- A root with `aspect-ratio` and no width.
- `align-items: baseline` on a column.

`python3 -I scripts/check-reference.py render` before and after the
upgrade, then `replay` the old dumps on the new engine. That lists every
frame of your own screens that moved.
