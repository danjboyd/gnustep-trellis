# TrellisPreview on Windows (draft)

Status: port in progress. The source builds on MSYS2 CLANG64 except where
noted below; nothing here has been released.

## Toolchain

One toolchain, never mixed: **gnustep-cli v0.1.9, patched**, as an MSYS2
CLANG64 root (libobjc2 with blocks, gnustep-base, gnustep-gui and
gnustep-back 0.32 with the win32 server and cairo graphics, fonts through
fontconfig). Don't put MSYS2's own gnustep packages on the same PATH: the
toolchain's DLLs fail to load over them.

The toolchain's `GNUstep.conf` keeps user defaults in files
(`GNUSTEP_USER_DEFAULTS_DIR=GNUstep/Defaults`), not in the registry.

## Build

In the toolchain root's CLANG64 shell, with GNUstep set up there:

```sh
git clone https://github.com/danjboyd/gnustep-trellis.git && cd gnustep-trellis
. scripts/env.sh      # no ~/opt/trellis-toolchain: uses the GNUstep already set up
make -j4 hot_reload=no
make check            # engine and conformance (no GUI)
```

`TrellisPreview.app/TrellisPreview.exe`, `obj/trellis-render.exe` and
`obj/trellis-lint.exe` are built next to the libraries
(`libTrellis`, `libTrellisEngine` as DLLs).

## Isolation: test runs as a dedicated Windows user

Linux GUI checks run on a private Xvfb display with a private
`GNUSTEP_HOME`. Windows has no X display to hide, and the headless modes
never show a window (trellis-render draws into a bitmap; TrellisPreview
`--snapshot` has no run loop). But gnustep-base writes message-port names
to the user's registry (`HKCU\Software\GNUstepNSMessagePort`) on every
launch, whatever the private home. Dan's rule: test runs must not touch
his `HKCU`. So on Windows:

- every GUI run goes through `scripts/run-headless.sh`, which sets the
  private `GNUSTEP_HOME`/`HOME` (as Windows paths) and `TEMP`/`TMP`;
- it runs only as a **dedicated test user**: `TRELLIS_TEST_USER` must name
  the Windows user the process runs as. `run-headless.sh` and
  trellis-render both refuse (exit 3) otherwise;
- trellis-render also applies the same settings guard as on Linux: home,
  user Library and defaults directory must all resolve inside the private
  `GNUSTEP_HOME` (symlinks and junctions followed, names compared without
  case), and the real home is the profile folder the shell reports.

How the test user is set up (a separate account via `runas`, CI only, or a
separate VM) is Dan's decision (ask #8635).

## Parity matrix

`Tests/Parity/run.sh OUT` runs the same cases on Linux and Windows with a
synthetic fixture (`Tests/Parity/Parity.trellis` and its sample), and
`Tests/Parity/compare.py LINUX_OUT WINDOWS_OUT` compares the two.

| Case | What | Pass when |
|---|---|---|
| theme | each theme in `THEMES`, before its cases | `NAME.theme` is in the private home's `Library/Themes` or the toolchain's Local, Network or System `Themes` (otherwise that theme's cases are skipped) |
| open | TrellisPreview `--snapshot` + `--export-json`, 900x640 | PNG and frames JSON written, and the JSON names the requested theme |
| resize | the same window resized live (`--resize 520x640,340x640`) | a snapshot and JSON at each size |
| reload | `--watch 2` while the fixture, then its sample, are edited | each reload's JSON shows the edit |
| render | trellis-render at 900x640, same theme and appearance | its PNG equals the Preview snapshot, 0 differing pixels |
| refuse | trellis-render without a private `GNUSTEP_HOME` (stand-in `HOME`) | exit 3, nothing written |
| settings | the real `~/GNUstep` (`%USERPROFILE%\GNUstep` on Windows) | unchanged by the whole run |
| registry | Windows: `HKCU\Software\GNUstep*` of the user running it | reported (INFO), for the record |

Each case runs for every entry in `THEMES` (default `Adwaita`). An entry
is `NAME` or `NAME:APPEARANCES`: `THEMES="Adwaita WinUITheme:light"`.
Without a list, Adwaita runs in light and dark and any other theme in
light only. The theme check catches a missing bundle and a fallback to
GNUstep's default theme; it can't tell whether a bundle that loads draws
correctly, which is what the snapshots are for.

Across platforms pixels aren't comparable (fonts and their metrics
differ), so `compare.py` checks structure for every frames JSON both runs
wrote: the same view tree (classes, ids, nesting), the same Tab order, and
every frame within 24 px (`--tolerance`); lint findings that differ are
listed as warnings. Within one platform the pixel check is exact.

Themes that exist on one platform only are paired with `--theme-map`:

```sh
# Linux: THEMES="Adwaita GNUstep"; Windows: THEMES="WinUITheme GNUstep"
python3 -I Tests/Parity/compare.py LINUX_OUT WINDOWS_OUT --theme-map Adwaita=WinUITheme
```

GNUstep's default theme builds everywhere, so `GNUstep` gives a
same-theme comparison on both platforms. The reload case uses the first
theme in `THEMES`.

On Linux: `make check-parity` (needs Xvfb and Adwaita).

## Runtime contract (for packaging)

- Ship: `TrellisPreview.app` (executable and Resources), `libTrellis` and
  `libTrellisEngine`; not the tools (trellis-render refuses to run outside
  an isolated setup, and trellis-lint is for agents).
- Runtime: the gnustep-cli v0.1.9 patched stack above, with its
  `GNUstep.conf` (point `GNUSTEP_CONFIG_FILE` at it, or the host's is
  read), DejaVu fonts, and `Adwaita.theme` (danjboyd/plugins-themes-Adwaita
  at 9c25a68) in a `Library/Themes` folder GNUstep searches.
- Settings: TrellisPreview writes nothing to the user's defaults (the
  appearance switch uses the argument domain and relaunches itself).
- Build with `make hot_reload=no`.
- Themes: Adwaita (danjboyd/plugins-themes-Adwaita at 9c25a68) doesn't
  build on Windows: its GNOME adapters (X11 window manager, portal file
  chooser and print dialog) are Linux-only. On Windows the candidate is
  WinUITheme (danjboyd/plugins-themes-winuitheme), which the appearance
  switch also drives (`WinUIThemeColorScheme` 1 or 2, argument domain
  only). It ships once the matrix has passed with it on Windows.
- File association (`.trellis` opens TrellisPreview): Dan's decision, in
  the release proposal.
