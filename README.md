<div align="center">

# Plug-and-Play Systolic NPU

<img src="https://img.shields.io/badge/Hardware-SystemVerilog-blue?style=for-the-badge" alt="SystemVerilog" />
<img src="https://img.shields.io/badge/Architecture-Systolic%20Array-blueviolet?style=for-the-badge" alt="Systolic Array" />
<img src="https://img.shields.io/badge/Interface-AXI4--Stream-ff69b4?style=for-the-badge" alt="AXI4-Stream" />
<img src="https://img.shields.io/badge/Precision-INT8%2FINT32-orange?style=for-the-badge" alt="INT8/INT32" />
<img src="https://img.shields.io/badge/Status-Verified-success?style=for-the-badge" alt="Verified" />

<br/>

<p align="center">
A fully verified, parameterizable Weight-Stationary Systolic Array designed for edge AI matrix multiplications.<br/>
Upgraded with AXI4-Stream interfaces and internal hardware skewing for zero-overhead SoC integration.
</p>

</div>

---

<div align="center">
  <h2>Features</h2>
</div>

- **True Systolic Grid**: Data flows cyclically through processing elements (PEs) across both dimensions. No global broadcasting (reduces fan-out and maximizes Fmax).
- **Internal Pipeline Skewing**: Hardened `skew_buffer` and `unskew_buffer` layers handle the diagonalizing of matrices. The SoC simply streams normal matrices in and out without software-side pre-processing!
- **Standard AXI4-Stream**: Standardized handshakes (`tvalid`, `tready`, `tdata`, `tlast`) make it trivial to hook this IP up to DMA controllers and bus interconnects.
- **Parametrizable**: Easily adjustable `N`, `DATA_WIDTH`, and `ACC_WIDTH` via `npu_defines.sv`.
- **Verified**: Fully tested using Cocotb + Verilator, with 100% functional testbench coverage.

---

<div align="center">
  <h2>Interfaces</h2>
</div>

| Interface | Type | Description |
|-----------|------|-------------|
| `s_axis_w` | AXI4-Stream Input | Streams `N` weight vectors to load the stationary PEs. |
| `s_axis_a` | AXI4-Stream Input | Streams `N` activation vectors to multiply against the weights. |
| `m_axis_out`| AXI4-Stream Output | Outputs `N` partial sum vectors. |

---

<div align="center">
  <h2>Quick Start</h2>
</div>

1. Drive `s_axis_w` with `N` rows of weights. The internal FSM automatically loads them into the grid.
2. Drive `s_axis_a` with `N` rows of activations. The hardware automatically skews the data and pushes it through the systolic array.
3. Assert `tlast` on the final activation row. The FSM automatically flushes the pipeline and outputs the final `N x N` matrix via `m_axis_out`.

---

<div align="center">
  <h2>Directory Structure</h2>
</div>

- `rtl/pe.v` : Processing Element (MAC + Weight Register).
- `rtl/systolic_array.v` : Generates the NxN array of PEs.
- `rtl/npu_defines.sv` : Parameterization macros and type definitions.
- `rtl/skew_buffers.v` : Hardware input skewing and output unskewing pipeline.
- `rtl/axis_npu.v` : The top module, containing the AXI4-Stream wrapper and state machine.
- `tb/test_npu.py` : Comprehensive Cocotb UVM-like testbench.
- `tb/Makefile` : Makefile to run the simulation (Verilator + Coverage enabled by default).

---

<div align="center">
  <h2>The Testbench Features</h2>
</div>

The Cocotb testbench located at `tb/test_npu.py` is written as an all-in-one comprehensive verification suite:
1. **UVM-like Architecture**: Separated into AXI4-Stream drivers, monitors, and a golden scoreboard.
2. **Regression Suite**: Contains multiple tests that run automatically in sequence.
3. **Directed Tests**: Tests `Identity`, `Zeros`, `Max Values`, and `Checkerboard` matrices to catch edge cases, in addition to purely random matrices.
4. **Code Coverage**: The `Makefile` enables `verilator --coverage` to track line, toggle, and structural coverage in the RTL.
5. **Functional Coverage**: Uses `cocotb_coverage` to track configuration metrics and ensure all directed test cases are hit.

---

<div align="center">
  <h2>Running the Verification</h2>
</div>

To run the full regression testbench and generate coverage:

```bash
cd tb
make clean
make
```

*(Note: If you are on Windows, you can run Verilator via WSL using `wsl bash -l -c "cd tb && make clean && make"`)*
