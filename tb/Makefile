SIM ?= verilator
TOPLEVEL_LANG ?= verilog

# Use relative paths to avoid GNU Make splitting the absolute path on the space in "8x8 NPU"
VERILOG_SOURCES += ../rtl/pe.v
VERILOG_SOURCES += ../rtl/systolic_array.v
VERILOG_SOURCES += ../rtl/npu_core.v

# Enable code coverage in Verilator (Line, Toggle, and Structural)
EXTRA_ARGS += --coverage

TOPLEVEL = npu_core
MODULE = test_npu

include $(shell cocotb-config --makefiles)/Makefile.sim
