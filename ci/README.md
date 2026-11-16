# CI

The workflow is `.github/workflows/ci.yml`. The repo is public, so the Linux
job runs without spending Actions minutes. The macOS job runs only on a manual
dispatch with `macos: true` (macOS runners bill at 10x on private repos).

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
6. `make check-gui` under Xvfb (fails if any view check fails).

**macOS** (macos-15): the same with `Makefile.macos` (`gui check`, conformance
gate against `macos.json`, importer tests, window-free dark renders). Present
but manual-only: it runs on a workflow dispatch with `macos: true`.

## Minutes

Public repositories don't consume Actions minutes for standard runners. The
earlier estimate for a private repo (about 5 min a Linux run) is kept in the
history of this file.
