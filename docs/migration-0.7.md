# Moving a screen from 0.5.x to 0.7

Three layout results changed between 0.5.1 and 0.7. Each is closer to the
browser. `Tests/Reference/migration.trellis` shows all three with made-up
content, and `scripts/check-migration.py` checks the frames (0.7 values;
`--was --render <0.5.1 trellis-render>` checks the old ones).

| Since | What changed | 0.5.1 | 0.7 |
|---|---|---|---|
| 0.6 | A `display: block` box's children never shrink or flex. A `height: 100px` child of a 50px block overflows. | shrank to 45 | 100 |
| 0.6 | `height: 50%` resolves only against a definite height. Under an auto-height column, or in an item that isn't stretched (`align-self: flex-start`), it acts as `auto`. | 7 / 20 | 0 / content (40) |
| 0.6 | `margin-`, `padding-` and `inset-inline-*` follow the box's `direction`. Under `rtl`, `margin-inline-start` is the right margin. | always left | right (x 170 → 150) |
| 0.7 | Grid: an item spanning an empty `min-content`/`max-content` track and a growable one (CSSWG #3648) leaves the empty track at 0. The growable track takes the space. | empty track 51 / 1 | 0 |

**What to check in a screen:**
- **Blocks:** a `display: block` box whose children relied on shrinking.
  Use a `<column>` if they should flex.
- **Percentage heights:** a `height: N%` inside a box whose height comes
  from its content. Give the parent a height, or let it be stretched.
- **Logical properties:** `*-inline-*` properties inside `dir="rtl"` or
  `direction: rtl`.
- **Grids:** a grid with an empty intrinsic track (`min-content`,
  `max-content`, `auto`) and an item spanning it and a `minmax()` track.

`python3 -I scripts/check-reference.py render` before and after the
upgrade, then `replay` the old dumps on the new engine, lists every frame
of your own screens that moved.
