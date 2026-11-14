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
	Source/Engine/TRMarkup.m
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
TOOL_NAME = trellis-case trellis-lint trellis-render
trellis-case_OBJC_FILES = Tools/trellis-case.m
trellis-case_TOOL_LIBS = -lTrellisEngine
trellis-lint_OBJC_FILES = Tools/trellis-lint.m
trellis-lint_TOOL_LIBS = -lTrellisEngine
trellis-render_OBJC_FILES = Tools/trellis-render.m Tools/TRSamples.m
trellis-render_TOOL_LIBS = -lTrellis -lTrellisEngine
trellis-render_NEEDS_GUI = yes

ADDITIONAL_OBJCFLAGS += -fobjc-arc -fblocks -Wall -Wno-unused-function
ADDITIONAL_INCLUDE_DIRS += -ISource/Engine -ISource/View
ADDITIONAL_LIB_DIRS += -L./obj -L./$(GNUSTEP_OBJ_DIR)

include $(GNUSTEP_MAKEFILES)/library.make
include $(GNUSTEP_MAKEFILES)/tool.make

# --- Tests -------------------------------------------------------------------
CASE_RUNNER = LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH ./obj/trellis-case

LINT = LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH ./obj/trellis-lint

check:: all
	@echo "== engine cases"
	@$(CASE_RUNNER) Tests/Engine/cases
	@echo "== .trellis files (syntax, styles, bindings)"
	@$(LINT) Examples/TrellisDemo/AskDetail.trellis --owner Examples/TrellisDemo/AskDetailController.h
	@$(LINT) Examples/TrellisDemo/Settings.trellis --owner Examples/TrellisDemo/SettingsController.h
	@if [ -d Tests/Conformance/cases ] && [ -n "$$(ls -A Tests/Conformance/cases 2>/dev/null)" ]; then \
	  echo "== conformance (report only; does not fail the build)"; \
	  $(CASE_RUNNER) Tests/Conformance/cases | tail -20 || true; \
	fi
