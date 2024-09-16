# ==============================================================================
# TEMPO: Static Timing Analysis & Logic Synthesis Engine
# Makefile for C Acceleration Library and Test Execution
# ==============================================================================

CC ?= clang
TCLSH ?= /opt/homebrew/opt/tcl-tk@8/bin/tclsh

UNAME_S := $(shell uname -s)

# Detect Tcl include directory
TCL_INC ?= $(shell if [ -d /opt/homebrew/opt/tcl-tk@8/include/tcl-tk ]; then echo /opt/homebrew/opt/tcl-tk@8/include/tcl-tk; elif [ -d /usr/include/tcl8.6 ]; then echo /usr/include/tcl8.6; else echo /usr/include; fi)

CFLAGS ?= -O3 -Wall -fPIC -I$(TCL_INC)

ifeq ($(UNAME_S),Darwin)
    SHLIB_EXT := dylib
    SHLIB_FLAGS := -dynamiclib -undefined dynamic_lookup
else
    SHLIB_EXT := so
    SHLIB_FLAGS := -shared
endif

TARGET := src/c/tempo_accel.$(SHLIB_EXT)
SRC := src/c/tempo_accel.c

.PHONY: all accel test check clean

all: accel

accel: $(TARGET)

$(TARGET): $(SRC)
	@mkdir -p src/c
	$(CC) $(CFLAGS) $(SHLIB_FLAGS) $< -o $@
	@echo "[BUILD] Built native C acceleration library: $@"

test: accel
	@echo "================================================================================"
	@echo "RUNNING TEMPO TEST SUITE"
	@echo "================================================================================"
	@for t in tests/unit/test_*.tcl; do \
		echo "=== Running $$t ==="; \
		$(TCLSH) $$t || exit 1; \
	done
	@if [ -d tests/integration ]; then \
		for t in tests/integration/test_*.tcl; do \
			echo "=== Running $$t ==="; \
			$(TCLSH) $$t || exit 1; \
		done; \
	fi
	@echo "================================================================================"
	@echo "ALL TESTS PASSED SUCCESSFULLY"
	@echo "================================================================================"

check:
	python3 scripts/check_no_em_dash.py

clean:
	rm -f src/c/*.dylib src/c/*.so src/c/*.o
	rm -rf build/
