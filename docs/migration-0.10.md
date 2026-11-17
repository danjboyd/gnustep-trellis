# Moving a screen from 0.9 to 0.10

Two layout results change in 0.10 (unreleased), each closer to the
browser. For earlier changes, see [migration-0.9.md](migration-0.9.md).

| What changed | 0.9 | 0.10 |
|---|---|---|
| A **shrink-to-fit grid with less space than its min-content** (for example in a narrow `align-items: flex-start` column, or at `width: min-content`) keeps its tracks' minimum sizes and overflows the space. Percentage columns resolve against that width, and auto-fill/auto-fit columns count against a definite `max-width`. | squeezed to the available width (0 for `width: min-content`) | at least the sum of its track bases |
| **`min-height` / `max-height: min-content`** (or `max-content`, `fit-content`) on a wrapping column with a definite `height` breaks lines at that height and takes the longest line. `height: min-content` is unchanged. | every item in one line | the longest line at the box's height |

**What to check in a screen:**
- A `display: grid` box that isn't stretched by its parent, in a space
  narrower than its content.
- A `flex-wrap` column with a size keyword on `min-height` or `max-height`.

`python3 -I scripts/check-reference.py render` before and after the
upgrade, then `replay` the old dumps on the new engine. That lists every
frame of your own screens that moved.
