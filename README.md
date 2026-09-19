# 8x8 Plug-and-Play Systolic NPU 🚀 

A fully verified, parameterizable 8x8 Weight-Stationary Systolic Array designed for edge AI matrix multiplications. Now upgraded with **AXI4-Stream** interfaces and internal hardware skewing!

## Architecture Features
- **True Systolic Grid**: Data flows cyclically through processing elements (PEs) across both dimensions. No global broadcasting (reduces fan-out and maximizes Fmax).
- **Internal Pipeline Skewing**: Hardened `skew_buffer` and `unskew_buffer` layers handle the diagonalizing of matrices. The SoC simply streams normal matrices in and out without software-side pre-processing!
- **Standard AXI4-Stream**: Standardized handshakes (`tvalid`, `tready`, `tdata`, `tlast`) make it trivial to hook this IP up to DMA controllers and bus interconnects.
- **Parametrizable**: Easily adjustable `N`, `DATA_WIDTH`, and `ACC_WIDTH` via `npu_defines.sv`.
- **Verified**: Fully tested using Cocotb + Verilator, with 100% functional testbench coverage.

## Interfaces
| Interface | Type | Description |
|-----------|------|-------------|
| `s_axis_w` | AXI4-Stream Input | Streams `N` weight vectors to load the stationary PEs. |
| `s_axis_a` | AXI4-Stream Input | Streams `N` activation vectors to multiply against the weights. |
| `m_axis_out`| AXI4-Stream Output | Outputs `N` partial sum vectors. |

## Quick Start
1. Drive `s_axis_w` with $N$ rows of weights. The internal FSM automatically loads them into the grid.
2. Drive `s_axis_a` with $N$ rows of activations. The hardware automatically skews the data and pushes it through the systolic array.
3. Assert `tlast` on the final activation row. The FSM automatically flushes the pipeline and outputs the final $N \times N$ matrix via `m_axis_out`.

## Verification
To run the automated Cocotb regression suite:
```bash
cd tb
make clean
make
```

> **Note**: Uses cocotb and Verilator for cycle-accurate open-source verification.
