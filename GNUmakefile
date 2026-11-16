# Trellis - responsive CSS box layout for GNUstep and Cocoa.
#
#   . scripts/env.sh      # or any GNUstep (clang, libobjc2, ARC) environment
#   make
#   make check
#
# On macOS without GNUstep, use Makefile.macos.

ifeq ($(GNUSTEP_MAKEFILES),)
  GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
  $(error GNUstep is not set up: source GNUstep.sh or scripts/env.sh first)
endif

include $(GNUSTEP_MAKEFILES)/common.make

# make shared=no builds Trellis's own libraries as static archives. Link
# GNUstep itself dynamically all the same: gnustep-make would add -static
# to every link, and a system GNUstep ships no static libgnustep-base.
ifeq ($(shared),no)
  STATIC_LDFLAGS :=
endif

PACKAGE_NAME = Trellis
VERSION = 0.1.0

LIBRARY_NAME = libTrellisEngine libTrellis

# --- The engine: Foundation only -------------------------------------------
libTrellisEngine_OBJC_FILES = \
	Source/Engine/TRStyle.m \
	Source/Engine/TRNode.m \
	Source/Engine/TRLayout.m \
	Source/Engine/TRContainerQuery.m \
	Source/Engine/TRLint.m \
	Source/Engine/TRMarkup.m \
	Source/Engine/TRGrid.m
libTrellisEngine_HEADER_FILES_DIR = Source/Engine
libTrellisEngine_HEADER_FILES_INSTALL_DIR = Trellis
libTrellisEngine_HEADER_FILES = TRTypes.h TRStyle.h TRNode.h TRLint.h TRMarkup.h TrellisEngine.h

# --- The view layer: AppKit (GNUstep or Apple) --------------------------------
libTrellis_OBJC_FILES = \
	Source/View/TRBoxView.m \
	Source/View/TRViewMeasure.m \
	Source/View/TRLoader.m
libTrellis_HEADER_FILES_DIR = Source/View
libTrellis_HEADER_FILES_INSTALL_DIR = Trellis
libTrellis_HEADER_FILES = TRBoxView.h TRViewMeasure.h TRLoader.h
libTrellis_NEEDS_GUI = yes
libTrellis_LIBRARIES_DEPEND_UPON = -lTrellisEngine $(GUI_LIBS) $(FND_LIBS) $(OBJC_LIBS)

# --- Tools ------------------------------------------------------------------
TOOL_NAME = trellis-case trellis-lint trellis-render trellis-bench
trellis-case_OBJC_FILES = Tools/trellis-case.m
trellis-case_TOOL_LIBS = -lTrellisEngine
trellis-bench_OBJC_FILES = Tools/trellis-bench.m
trellis-bench_TOOL_LIBS = -lTrellisEngine
trellis-lint_OBJC_FILES = Tools/trellis-lint.m
trellis-lint_TOOL_LIBS = -lTrellisEngine
trellis-render_OBJC_FILES = Tools/trellis-render.m Tools/TRSamples.m
trellis-render_TOOL_LIBS = -lTrellis -lTrellisEngine
trellis-render_NEEDS_GUI = yes

# --- Trellis Preview app -----------------------------------------------------
APP_NAME = TrellisPreview
TrellisPreview_OBJC_FILES = Tools/TrellisPreview/TPController.m
TrellisPreview_GUI_LIBS = -lTrellis -lTrellisEngine
TrellisPreview_MAIN_MODEL_FILE =

ADDITIONAL_OBJCFLAGS += -fobjc-arc -fblocks -Wall -Wno-unused-function
ADDITIONAL_INCLUDE_DIRS += -ISource/Engine -ISource/View
ADDITIONAL_LIB_DIRS += -L./obj -L./$(GNUSTEP_OBJ_DIR)

include $(GNUSTEP_MAKEFILES)/library.make
include $(GNUSTEP_MAKEFILES)/tool.make
include $(GNUSTEP_MAKEFILES)/application.make

# gnustep-make builds the two libraries in parallel under make -j, but
# libTrellis links against libTrellisEngine: build the engine first.
libTrellis.all.library.variables: libTrellisEngine.all.library.variables

# --- Tests -------------------------------------------------------------------
# The conformance report: each failing case id, then the totals, per-suite
# rates and skip reasons.
CONF_SUMMARY = sed -n -e 's/^FAIL \([^ :]*\).*/  fail: \1/p' -e '/^PASS /,$$p'
CASE_RUNNER = LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH ./obj/trellis-case

LINT = LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH ./obj/trellis-lint

check:: all
	@echo "== engine cases"
	@$(CASE_RUNNER) Tests/Engine/cases
	@echo "== .trellis files (syntax, styles, bindings)"
	@$(LINT) Examples/TrellisDemo/AskDetail.trellis --owner Examples/TrellisDemo/AskDetailController.h
	@$(LINT) Examples/TrellisDemo/Settings.trellis --owner Examples/TrellisDemo/SettingsController.h
	@$(LINT) Examples/TrellisDemo/Dashboard.trellis --owner Examples/TrellisDemo/DashboardController.h
	@LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH Tests/Markup/run.sh
	@if [ -d Tests/Conformance/cases ] && [ -n "$$(ls -A Tests/Conformance/cases 2>/dev/null)" ]; then \
	  echo "== conformance (report only; does not fail the build)"; \
	  $(CASE_RUNNER) Tests/Conformance/cases | $(CONF_SUMMARY) || true; \
	fi

# Record this platform's results in docs/conformance/linux.json and
# regenerate the README table (scripts/conformance-summary.py).
conformance-record: all
	LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH python3 -I scripts/conformance-summary.py record --platform linux --runner ./obj/trellis-case
	python3 -I scripts/conformance-summary.py table

# View-level checks that need a GUI: built here and run headless under
# scripts/run-headless.sh (private Xvfb and GNUSTEP_HOME). Not part of
# make check, which needs no display.
GUI_TEST_FLAGS = $(shell gnustep-config --objc-flags) -fobjc-arc -fblocks -ISource/View -ISource/Engine
GUI_TEST_LIBS = -L./obj -lTrellis -lTrellisEngine $(shell gnustep-config --gui-libs)

check-gui:: all
	@mkdir -p obj/gui-tests
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/size-for-width.m -o obj/gui-tests/size-for-width $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/preview-open-file.m -o obj/gui-tests/preview-open-file $(GUI_TEST_LIBS)
	@echo "== view checks (headless)"
	@LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH timeout 60 scripts/run-headless.sh obj/gui-tests/size-for-width 2>&1 | grep -v _NET_WORKAREA | tail -1
	@LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH timeout 60 scripts/run-headless.sh obj/gui-tests/preview-open-file $(CURDIR)/Examples/TrellisDemo/Settings.trellis 2>&1 | grep -v _NET_WORKAREA | tail -1

