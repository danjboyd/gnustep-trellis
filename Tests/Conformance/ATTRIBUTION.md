# Third-party test data: attribution and licences

The conformance cases under `cases/` are **derived** from the projects
below. They aren't verbatim copies: `tools/import_yoga.py` and
`tools/import_wpt.py` translate each upstream test's input tree and
expected layout into Trellis's JSON case format
(docs/test-case-format.md). Each case's `source` block records its
upstream file, test, commit and licence.

The cases keep their original licences, reproduced in full below, and are
not covered by Trellis's LGPL. Separate copies are in [LICENSES/](LICENSES/).

| Suite | Upstream | Imported from | Licence |
|---|---|---|---|
| `yoga` | https://github.com/facebook/yoga: `tests/generated/*.cpp` (generated from `gentest/fixtures/*.html`) | commit `cac7b345c06804703dc6868f740f04ad8a863f27` | MIT |
| `wpt` | https://github.com/web-platform-tests/wpt: `css/css-flexbox` tests using `resources/check-layout-th.js` | commit `76f3efc65c27333e528675406167145735718fab` | BSD-3-Clause |
| `wpt-grid` | https://github.com/web-platform-tests/wpt: `css/css-grid` tests using `resources/check-layout-th.js` | commit `76f3efc65c27333e528675406167145735718fab` | BSD-3-Clause |
| `wpt-sizing` | https://github.com/web-platform-tests/wpt: `css/css-sizing` tests using `resources/check-layout-th.js` | commit `76f3efc65c27333e528675406167145735718fab` | BSD-3-Clause |

## Yoga: MIT License

```
MIT License

Copyright (c) Facebook, Inc. and its affiliates.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## web-platform-tests: 3-Clause BSD License

```
# The 3-Clause BSD License

Copyright © web-platform-tests contributors

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Re-importing

    git clone --depth 1 https://github.com/facebook/yoga /tmp/yoga
    git clone --depth 1 --filter=blob:none --sparse https://github.com/web-platform-tests/wpt /tmp/wpt
    git -C /tmp/wpt sparse-checkout set --no-cone /LICENSE.md css/css-flexbox css/css-grid css/css-sizing css/support resources /fonts/ahem.css
    rm -rf Tests/Conformance/cases/yoga Tests/Conformance/cases/wpt Tests/Conformance/cases/wpt-grid Tests/Conformance/cases/wpt-sizing
    python3 -I Tests/Conformance/tools/import_yoga.py /tmp/yoga Tests/Conformance/cases/yoga
    python3 -I Tests/Conformance/tools/import_wpt.py  /tmp/wpt  Tests/Conformance/cases/wpt
    python3 -I Tests/Conformance/tools/import_wpt.py  /tmp/wpt  Tests/Conformance/cases/wpt-grid css/css-grid wpt-grid
    python3 -I Tests/Conformance/tools/import_wpt.py  /tmp/wpt  Tests/Conformance/cases/wpt-sizing css/css-sizing wpt-sizing

**Before replacing the cases with a newer WPT snapshot**, import into a
scratch directory and review what changed:

    python3 -I Tests/Conformance/tools/import_wpt.py /tmp/wpt /tmp/new/wpt-grid css/css-grid wpt-grid
    python3 -I Tests/Conformance/tools/snapshot_diff.py Tests/Conformance/cases/wpt-grid /tmp/new/wpt-grid

It matches cases by file and input (not by their positional index) and
lists cases whose expectations upstream **revised** (same input, new
numbers: the engine may need to follow), whose input changed, and those
added, removed or only renumbered. It exits non-zero when anything but the
recorded commit changed. `--json` gives the same summary for scripts.

`reference/` holds a Yoga-backed runner used to sanity-check the importers:
`make -f Tests/Conformance/Makefile.macos check-reference YOGA=/tmp/yoga`.
