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
VERSION = 0.10.1

LIBRARY_NAME = libTrellisEngine libTrellis

# --- The engine: Foundation only -------------------------------------------
libTrellisEngine_OBJC_FILES = \
	Source/Engine/TRStyle.m \
	Source/Engine/TRNode.m \
	Source/Engine/TRLayout.m \
	Source/Engine/TRContainerQuery.m \
	Source/Engine/TRLint.m \
	Source/Engine/TRMarkup.m \
	Source/Engine/TRGrid.m \
	Source/Engine/TRVirtualLayout.m
libTrellisEngine_HEADER_FILES_DIR = Source/Engine
libTrellisEngine_HEADER_FILES_INSTALL_DIR = Trellis
libTrellisEngine_HEADER_FILES = TRTypes.h TRStyle.h TRNode.h TRLint.h TRMarkup.h TRVirtualLayout.h TrellisEngine.h

# --- The view layer: AppKit (GNUstep or Apple) --------------------------------
libTrellis_OBJC_FILES = \
	Source/View/TRBoxView.m \
	Source/View/TRViewMeasure.m \
	Source/View/TRLoader.m \
	Source/View/TRVirtualBox.m \
	Source/View/TRSplitView.m
libTrellis_HEADER_FILES_DIR = Source/View
libTrellis_HEADER_FILES_INSTALL_DIR = Trellis
libTrellis_HEADER_FILES = TRBoxView.h TRViewMeasure.h TRLoader.h TRVirtualBox.h TRSplitView.h
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
# make hot_reload=no compiles TRLoader's dev hot-reload out (release builds).
ifeq ($(hot_reload),no)
ADDITIONAL_OBJCFLAGS += -DTR_NO_HOT_RELOAD
endif
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
	@echo "== virtual layout"
	@$(CC) $(shell gnustep-config --objc-flags) -fobjc-arc -fblocks -ISource/Engine Tests/Engine/virtual-layout.m \
	  -o obj/virtual-layout -L./obj -lTrellisEngine $(shell gnustep-config --base-libs)
	@LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH ./obj/virtual-layout
	@echo "== custom properties"
	@$(CC) $(shell gnustep-config --objc-flags) -fobjc-arc -fblocks -ISource/Engine Tests/Engine/custom-properties.m \
	  -o obj/custom-properties -L./obj -lTrellisEngine $(shell gnustep-config --base-libs)
	@LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH ./obj/custom-properties
	@echo "== touch-target lint"
	@$(CC) $(shell gnustep-config --objc-flags) -fobjc-arc -fblocks -ISource/Engine Tests/Engine/lint-targets.m \
	  -o obj/lint-targets -L./obj -lTrellisEngine $(shell gnustep-config --base-libs)
	@LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH ./obj/lint-targets
	@echo "== markup parsing scale"
	@$(CC) $(shell gnustep-config --objc-flags) -fobjc-arc -fblocks -ISource/Engine Tests/Engine/markup-scale.m \
	  -o obj/markup-scale -L./obj -lTrellisEngine $(shell gnustep-config --base-libs)
	@LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH ./obj/markup-scale
	@echo "== logical sides in styles"
	@$(CC) $(shell gnustep-config --objc-flags) -fobjc-arc -fblocks -ISource/Engine Tests/Engine/logical-style.m \
	  -o obj/logical-style -L./obj -lTrellisEngine $(shell gnustep-config --base-libs)
	@LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH ./obj/logical-style
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
# Frame replay (scripts/check-reference.py): the golden dumps in
# Tests/Reference/dumps and dogfood/frames, from either platform, laid out
# again by this engine; then a self-test that a changed geometry value in
# each dump is caught. Engine only: no display needed.
check-reference: all
	LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH python3 -I scripts/check-reference.py replay --runner ./obj/trellis-case
	LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH python3 -I scripts/check-reference.py selftest --runner ./obj/trellis-case

# The 0.5.x to 0.7 migration fixture (scripts/check-migration.py): renders
# Tests/Reference/migration.trellis headless and checks the frames that
# moved. Needs Xvfb (scripts/run-headless.sh).
check-migration: all
	scripts/run-headless.sh env LD_LIBRARY_PATH=$(CURDIR)/obj:$$LD_LIBRARY_PATH python3 -I scripts/check-migration.py --render $(CURDIR)/obj/trellis-render

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
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/key-view-loop.m -o obj/gui-tests/key-view-loop $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/accessibility.m -o obj/gui-tests/accessibility $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/hot-reload.m -o obj/gui-tests/hot-reload $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/key-view-hang.m -o obj/gui-tests/key-view-hang $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/dealloc-pending-layout.m -o obj/gui-tests/dealloc-pending-layout $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/virtual-box.m -o obj/gui-tests/virtual-box $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/virtual-bench.m -o obj/gui-tests/virtual-bench $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/layout-transition.m -o obj/gui-tests/layout-transition $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/rich-text.m -o obj/gui-tests/rich-text $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/find-view-scroll.m -o obj/gui-tests/find-view-scroll $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/box-paint.m -o obj/gui-tests/box-paint $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/split.m -o obj/gui-tests/split $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/segmented.m -o obj/gui-tests/segmented $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/disabled.m -o obj/gui-tests/disabled $(GUI_TEST_LIBS)
	@$(CC) $(GUI_TEST_FLAGS) Tests/View/direction.m -o obj/gui-tests/direction $(GUI_TEST_LIBS)
	@echo "== view checks (headless)"
	@export LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH; status=0; \
	  timeout 60 scripts/run-headless.sh obj/gui-tests/size-for-width > obj/gui-tests/hook.log 2>&1 || status=1; \
	  grep -v _NET_WORKAREA obj/gui-tests/hook.log | tail -1; \
	  timeout 60 scripts/run-headless.sh obj/gui-tests/preview-open-file $(CURDIR)/Examples/TrellisDemo/Settings.trellis > obj/gui-tests/openfile.log 2>&1 || status=1; \
	  grep -v _NET_WORKAREA obj/gui-tests/openfile.log | tail -1; \
	  timeout 60 scripts/run-headless.sh obj/gui-tests/key-view-loop > obj/gui-tests/keyview.log 2>&1 || status=1; \
	  grep -v _NET_WORKAREA obj/gui-tests/keyview.log | tail -1; \
	  NSZombieEnabled=YES timeout 60 scripts/run-headless.sh obj/gui-tests/key-view-hang > obj/gui-tests/keyhang.log 2>&1 || status=1; \
	  if grep -q "deallocated instance" obj/gui-tests/keyhang.log; then echo "KEYHANG FAIL: message sent to a freed object"; status=1; fi; \
	  grep -v _NET_WORKAREA obj/gui-tests/keyhang.log | tail -1; \
	  timeout 60 scripts/run-headless.sh obj/gui-tests/accessibility > obj/gui-tests/a11y.log 2>&1 || status=1; \
	  grep -v _NET_WORKAREA obj/gui-tests/a11y.log | tail -1; \
	  timeout 60 scripts/run-headless.sh obj/gui-tests/hot-reload > obj/gui-tests/hotreload.log 2>&1 || status=1; \
	  grep -v _NET_WORKAREA obj/gui-tests/hotreload.log | tail -1; \
	  NSZombieEnabled=YES timeout 60 scripts/run-headless.sh obj/gui-tests/dealloc-pending-layout > obj/gui-tests/dealloc.log 2>&1 || status=1; \
	  if grep -q "deallocated instance" obj/gui-tests/dealloc.log; then echo "DEALLOC FAIL: message sent to a freed object"; status=1; fi; \
	  grep -v _NET_WORKAREA obj/gui-tests/dealloc.log | tail -1; \
	  NSZombieEnabled=YES timeout 120 scripts/run-headless.sh obj/gui-tests/virtual-box > obj/gui-tests/virtual.log 2>&1 || status=1; \
	  if grep -q "deallocated instance" obj/gui-tests/virtual.log; then echo "VIRTUALBOX FAIL: message sent to a freed object"; status=1; fi; \
	  grep -v _NET_WORKAREA obj/gui-tests/virtual.log | tail -1; \
	  NSZombieEnabled=YES timeout 60 scripts/run-headless.sh obj/gui-tests/layout-transition > obj/gui-tests/transition.log 2>&1 || status=1; \
	  if grep -q "deallocated instance" obj/gui-tests/transition.log; then echo "TRANSITION FAIL: message sent to a freed object"; status=1; fi; \
	  grep -v _NET_WORKAREA obj/gui-tests/transition.log | tail -1; \
	  NSZombieEnabled=YES timeout 60 scripts/run-headless.sh obj/gui-tests/rich-text > obj/gui-tests/richtext.log 2>&1 || status=1; \
	  if grep -q "deallocated instance" obj/gui-tests/richtext.log; then echo "RICHTEXT FAIL: message sent to a freed object"; status=1; fi; \
	  grep -v _NET_WORKAREA obj/gui-tests/richtext.log | tail -1; \
	  timeout 60 scripts/run-headless.sh obj/gui-tests/find-view-scroll > obj/gui-tests/findview.log 2>&1 || status=1; \
	  grep -v _NET_WORKAREA obj/gui-tests/findview.log | tail -1; \
	  timeout 60 scripts/run-headless.sh obj/gui-tests/box-paint > obj/gui-tests/boxpaint.log 2>&1 || status=1; \
	  grep -v _NET_WORKAREA obj/gui-tests/boxpaint.log | tail -1; \
	  NSZombieEnabled=YES timeout 60 scripts/run-headless.sh obj/gui-tests/split > obj/gui-tests/split.log 2>&1 || status=1; \
	  if grep -q "deallocated instance" obj/gui-tests/split.log; then echo "SPLIT FAIL: message sent to a freed object"; status=1; fi; \
	  grep -v _NET_WORKAREA obj/gui-tests/split.log | tail -1; \
	  NSZombieEnabled=YES timeout 60 scripts/run-headless.sh obj/gui-tests/segmented > obj/gui-tests/segmented.log 2>&1 || status=1; \
	  if grep -q "deallocated instance" obj/gui-tests/segmented.log; then echo "SEGMENTED FAIL: message sent to a freed object"; status=1; fi; \
	  grep -v _NET_WORKAREA obj/gui-tests/segmented.log | tail -1; \
	  NSZombieEnabled=YES timeout 60 scripts/run-headless.sh obj/gui-tests/disabled > obj/gui-tests/disabled.log 2>&1 || status=1; \
	  if grep -q "deallocated instance" obj/gui-tests/disabled.log; then echo "DISABLED FAIL: message sent to a freed object"; status=1; fi; \
	  grep -v _NET_WORKAREA obj/gui-tests/disabled.log | tail -1; \
	  NSZombieEnabled=YES timeout 60 scripts/run-headless.sh obj/gui-tests/direction > obj/gui-tests/direction.log 2>&1 || status=1; \
	  if grep -q "deallocated instance" obj/gui-tests/direction.log; then echo "DIRECTION FAIL: message sent to a freed object"; status=1; fi; \
	  grep -v _NET_WORKAREA obj/gui-tests/direction.log | tail -1; \
	  timeout 300 scripts/run-headless.sh obj/gui-tests/virtual-bench > obj/gui-tests/vbench.log 2>&1 || status=1; \
	  grep -v _NET_WORKAREA obj/gui-tests/vbench.log | tail -3; \
	  Tests/View/appearance.sh || status=1; \
	  Tests/View/scroll-container-query.sh || status=1; \
	  Tests/View/preview-export.sh || status=1; \
	  exit $$status
