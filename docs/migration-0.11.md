# Moving from 0.10 to 0.11 (draft)

0.11 has two layout changes and one change for anyone who runs
trellis-render outside `scripts/run-headless.sh`. For earlier changes, see
[migration-0.10.md](migration-0.10.md).

| What changed | 0.10 | 0.11 |
|---|---|---|
| **`safe` / `unsafe`** on `justify-items`, `justify-self`, `align-items`, `align-self` | the declaration was invalid and ignored | applied; in a grid, `safe` keeps an overflowing item at its area's start |
| **`initial`** on `width`, `height`, their `min-`/`max-` forms, `flex-basis` and the gaps | the declaration was ignored | the initial value (`auto`, `none` for max sizes, `0` for gaps) |
| **trellis-render's isolation guard** | `GNUSTEP_HOME` set and the home and Library under it | also the defaults directory; every path resolved (symlinks followed) and compared by component; dangling or unreadable components refused |

**What to check:**
- Stylesheets that already use `safe`, `unsafe` or `initial` on those
  properties: they were silently ignored before and now take effect.
- Scripts or harnesses that call trellis-render directly. If one now exits
  3 ("refusing to run"), make sure its private `GNUSTEP_HOME` holds the
  home, `GNUstep/Library` and `GNUstep/Defaults`. Either run it through
  `scripts/run-headless.sh`, or point `GNUSTEP_CONFIG_FILE` at a config
  that puts `GNUSTEP_USER_DEFAULTS_DIR` and the user Library inside the
  private home. A symlink from the private home back into the real
  `~/GNUstep` is refused on purpose.

`python3 -I scripts/check-reference.py render` before and after the
upgrade, then `replay` the old dumps on the new engine. That lists every
frame of your own screens that moved.

Windows support is a draft in 0.11 (docs/windows.md) and changes nothing
on Linux or macOS.
