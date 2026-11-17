# Moving a screen from 0.7 to 0.8

One layout rule changed in 0.8, and it brings Trellis closer to the
browser and to Yoga 3. For the 0.5.x to 0.7 changes, see
[migration-0.7.md](migration-0.7.md).

| Since | What changed | 0.7 | 0.8 |
|---|---|---|---|
| 0.8 | A `position: static` box is no longer a containing block. An abspos child of a static box is placed against the nearest positioned ancestor's padding box, or the layout root's. Insets, % sizes and % margins use that box. Auto insets keep the static position in the real parent. The child's frame is still relative to its parent. | placed against the static parent | placed against the positioned ancestor |

**Who is affected:** only screens that write `position: static`. Every box
defaults to `position: relative`, so if a screen never says `static`, its
frames are the same in 0.8.

**What to check in a screen:**
- **`position: static` on a box with `position: absolute` children**
  (directly, or through more static boxes). If those children should stay
  against that box, delete the `static`, or write `position: relative`.
- **Insets on a static box:** `static` has always ignored `top`, `left` and
  the rest. That hasn't changed.

The engine cases `engine/abspos_*` in `Tests/Engine/cases/absolute.json`
show the rule. `python3 -I scripts/check-reference.py render` before and
after the upgrade, then `replay` the old dumps on the new engine, lists
every frame of your own screens that moved.
