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

# --- The engine: Foundation only -------------------------------------------
LIBRARY_NAME = libTrellisEngine
libTrellisEngine_OBJC_FILES = \
	Source/Engine/TRStyle.m \
	Source/Engine/TRNode.m \
	Source/Engine/TRLayout.m \
	Source/Engine/TRContainerQuery.m
libTrellisEngine_HEADER_FILES_DIR = Source/Engine
libTrellisEngine_HEADER_FILES_INSTALL_DIR = Trellis
libTrellisEngine_HEADER_FILES = TRTypes.h TRStyle.h TRNode.h TrellisEngine.h

# --- Tools ------------------------------------------------------------------
TOOL_NAME = trellis-case
trellis-case_OBJC_FILES = Tools/trellis-case.m
trellis-case_TOOL_LIBS = -lTrellisEngine

ADDITIONAL_OBJCFLAGS += -fobjc-arc -fblocks -Wall -Wno-unused-function
ADDITIONAL_INCLUDE_DIRS += -ISource/Engine
ADDITIONAL_LIB_DIRS += -L./obj -L./$(GNUSTEP_OBJ_DIR)

include $(GNUSTEP_MAKEFILES)/library.make
include $(GNUSTEP_MAKEFILES)/tool.make

# --- Tests -------------------------------------------------------------------
CASE_RUNNER = LD_LIBRARY_PATH=./obj:$$LD_LIBRARY_PATH ./obj/trellis-case

check:: all
	@echo "== engine cases"
	@$(CASE_RUNNER) Tests/Engine/cases
	@if [ -d Tests/Conformance/cases ] && [ -n "$$(ls -A Tests/Conformance/cases 2>/dev/null)" ]; then \
	  echo "== conformance (report only; does not fail the build)"; \
	  $(CASE_RUNNER) Tests/Conformance/cases | tail -20 || true; \
	fi
