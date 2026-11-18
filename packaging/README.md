# Packaging assets

- `TrellisPreview.svg`: the TrellisPreview app icon, original artwork
  (Copyright (C) 2026 Dan Boyd, LGPL-2.1-or-later like the rest of
  Trellis). No third-party marks.
- `TrellisPreview.png` (256x256) and `TrellisPreview-1024.png`
  (1024x1024): rendered from the SVG with
  `magick -background none TrellisPreview.svg -resize NxN out.png`.

The runtime and theme contract for packages is in docs/windows.md.
