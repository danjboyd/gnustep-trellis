# CI (draft, not active)

`github-actions-ci.yml` is a GitHub Actions workflow kept **outside**
`.github/workflows/`, so it doesn't run. Running it spends Actions minutes
on this private repo, so it waits for the maintainer's approval.

To enable the Linux job: `git mv ci/github-actions-ci.yml .github/workflows/ci.yml`.

## What it runs

**Linux** (ubuntu-24.04), on pushes to `main` and on pull requests (docs-only
changes skipped; a newer push cancels an in-progress run):

1. apt build dependencies;
2. the GNUstep toolchain from `scripts/install-toolchain-debian.sh`, restored
   from the Actions cache (built from source only on a cache miss);
3. `make`, `make check` (engine cases, lint, markup, conformance report);
4. a conformance gate, `scripts/conformance-summary.py check --platform linux`:
   fails if any suite passes fewer cases than `docs/conformance/linux.json`;
5. the importer unit tests;
6. `make check-gui` under Xvfb, requiring `HOOK OK` and `APPEARANCE OK`.

**macOS** (macos-15): the same with `Makefile.macos` (`gui check`, conformance
gate against `macos.json`, importer tests, window-free dark renders). Present
but **disabled**: it runs only on a manual dispatch with `macos: true`.

## Minutes estimate (not yet measured; revise after the first runs)

| | Per run | Runs / month | Minutes / month |
|---|---|---|---|
| Linux, cached toolchain | ~5 min | 220–550 (10–25 pushes to main per working day) | **1,100–2,750** |
| Linux, cache miss | +~20 min | a few (script change, cache eviction after 7 idle days) | +~60 |
| macOS per push (10x multiplier) | ~4 min = 40 billed | 220–550 | 8,800–22,000 billed |
| macOS nightly, weekdays (10x) | ~4 min = 40 billed | 22 | ~880 billed |
| macOS manual only (10x) | ~4 min = 40 billed | ~10 | ~400 billed |

For scale: private repos include 2,000 (Free) or 3,000 (Pro/Team) minutes
a month, and macOS minutes count 10x against that. Overage was about
$0.008/min for Linux and $0.08/min for macOS when last checked; check the
current GitHub pricing before deciding. Linux-only stays near or inside the
included minutes. macOS per push would cost hundreds of dollars a month;
macOS nightly is roughly $5–10 a month of overage.
