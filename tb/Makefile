SIM ?= verilator
TOPLEVEL_LANG ?= verilog

# Use relative paths to avoid GNU Make splitting the absolute path on the space in "8x8 NPU"
VERILOG_SOURCES += ../rtl/pe.v
VERILOG_SOURCES += ../rtl/systolic_array.v
VERILOG_SOURCES += ../rtl/skew_buffers.v
VERILOG_SOURCES += ../rtl/max_pool_2x2.v
VERILOG_SOURCES += ../rtl/activation_pool.v
VERILOG_SOURCES += ../rtl/accumulator_pbuf.v
VERILOG_SOURCES += ../rtl/sram_buffers.v
VERILOG_SOURCES += ../rtl/layer_controller.v
VERILOG_SOURCES += ../rtl/npu_command_fifo.v
VERILOG_SOURCES += ../rtl/npu_top.v

# Enable code coverage in Verilator (Line, Toggle, and Structural)
EXTRA_ARGS += -I../rtl --coverage -DSIMULATION -Wno-fatal

TOPLEVEL = npu_top
MODULE = test_npu

include $(shell cocotb-config --makefiles)/Makefile.sim
