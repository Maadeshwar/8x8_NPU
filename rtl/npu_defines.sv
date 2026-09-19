`ifndef NPU_DEFINES_SV
`define NPU_DEFINES_SV

// -------------------------------------------------------------------------
// NPU Architecture Defines
// -------------------------------------------------------------------------

// Default Array Dimensions
`ifndef NPU_DIM
    `define NPU_DIM 8
`endif

// Default Data Widths
`ifndef NPU_DATA_WIDTH
    `define NPU_DATA_WIDTH 8
`endif

`ifndef NPU_ACC_WIDTH
    `define NPU_ACC_WIDTH 32
`endif

`endif // NPU_DEFINES_SV
