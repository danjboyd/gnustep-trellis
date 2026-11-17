# Moving a screen from 0.9 to 0.10

Several layout results change in 0.10 (unreleased), each closer to the
browser and each in a corner case. For earlier changes, see [migration-0.9.md](migration-0.9.md).

| What changed | 0.9 | 0.10 |
|---|---|---|
| A **shrink-to-fit grid with less space than its min-content** (for example in a narrow `align-items: flex-start` column, or at `width: min-content`) keeps its tracks' minimum sizes and overflows the space. Percentage columns resolve against that width, and auto-fill/auto-fit columns count against a definite `max-width`. | squeezed to the available width (0 for `width: min-content`) | at least the sum of its track bases |
| **`min-height` / `max-height: min-content`** (or `max-content`, `fit-content`) on a wrapping column with a definite `height` breaks lines at that height and takes the longest line. `height: min-content` is unchanged. | every item in one line | the longest line at the box's height |
| A **row item with `flex-shrink: 0`** and an auto width measures `height: fit-content` (or `min-content`, `max-content`) at its max-content width. | wrapped into the line's width | one line at its own width |
| **`height: stretch`** (or min-height/max-height) on a **column item** when the column has no definite height. | the available height | auto (none for max-height) |
| **`width: stretch` on a column item** (height on a row item) in a **wrapping** container. | the container's width | its flex line's width, which may be wider |
| **Size keywords on an abspos box** with `left`/`right` (`top`/`bottom`). | the whole containing block | the containing block less those insets |
| A **root with no available width, a `max-width` and a larger `min-width`**. | content fitted to the max | the min wins |
| **`justify-items: auto`** on a grid. | items not stretched (0 width when auto) | normal: auto-width items stretch |
| A **`width: max-content` grid with a spanning item** across `auto` columns. | spanning item's extra width ignored | auto tracks grow to fit it |
| **auto-fill/auto-fit columns** in a shrink-to-fit grid with a `min-width` but no `max-width`. | counted against the space | the fewest that reach the min-width |
| **`aspect-ratio` with a definite `min-height`** and a `min-content`/`max-content` width keyword (often on `max-width`). | the content width | at least min-height × ratio |

**What to check in a screen:**
- A `display: grid` box that isn't stretched by its parent, in a space
  narrower than its content.
- A `flex-wrap` column with a size keyword on `min-height` or `max-height`.
- Size keywords (`stretch`, `fit-content`, `min-content`, `max-content`) on
  flex items, abspos boxes and boxes with `aspect-ratio`.
- `justify-items: auto` on a grid.

`python3 -I scripts/check-reference.py render` before and after the
upgrade, then `replay` the old dumps on the new engine. That lists every
frame of your own screens that moved.
