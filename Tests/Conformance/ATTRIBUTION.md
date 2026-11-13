# Third-party test data

The conformance cases under `cases/` are derived from the following projects.
Each case records its origin in its `source` field (suite, file, test name,
upstream commit, licence).

| Suite | Upstream | Licence | Copy of licence |
|-------|----------|---------|-----------------|
| `yoga` | https://github.com/facebook/yoga (`gentest/fixtures`, via `tests/generated`) | MIT, Copyright (c) Meta Platforms, Inc. and affiliates | [LICENSES/yoga-MIT.txt](LICENSES/yoga-MIT.txt) |
| `wpt` | https://github.com/web-platform-tests/wpt (`css/css-flexbox`, tests using `check-layout-th.js`) | 3-Clause BSD, Copyright (c) web-platform-tests contributors | [LICENSES/wpt-BSD-3-Clause.md](LICENSES/wpt-BSD-3-Clause.md) |

The cases are mechanical translations (see `tools/import_*.py`) of the
upstream inputs and browser-measured expected layouts into Trellis's JSON
case format. They are redistributed under their original licences; they are
not covered by Trellis's LGPL.
