<div align="center">

# Plug-and-Play Systolic NPU Subsystem

<img src="https://img.shields.io/badge/Hardware-SystemVerilog-blue?style=for-the-badge" alt="SystemVerilog" />
<img src="https://img.shields.io/badge/Architecture-Systolic%20Array-blueviolet?style=for-the-badge" alt="Systolic Array" />
<img src="https://img.shields.io/badge/Interface-Memory%20Mapped-ff69b4?style=for-the-badge" alt="Memory Mapped" />
<img src="https://img.shields.io/badge/Precision-INT8%2FINT32-orange?style=for-the-badge" alt="INT8/INT32" />
<img src="https://img.shields.io/badge/Status-Verified-success?style=for-the-badge" alt="Verified" />

<br/>

<p align="center">
A fully verified, parameterizable Weight-Stationary Systolic NPU Subsystem designed for edge AI inference.<br/>
Features an integrated Layer Controller, internal SRAMs, and a hardware post-processing pipeline for zero-overhead SoC integration.
</p>

</div>

---

<div align="center">
  <h2>Features</h2>
</div>

- **True Systolic Grid**: Data flows cyclically through processing elements (PEs) across both dimensions. No global broadcasting (reduces fan-out and maximizes Fmax).
- **Integrated Control & Storage**: Includes an internal 3-Stage FSM `layer_controller` and tightly coupled SRAMs (`IBUF`, `WBUF`, `OBUF`) to operate completely autonomously from the CPU.
- **Hardware Tiler**: Nested loop controller allows scheduling entire multi-dimensional tensor operations with a single configuration command.
- **Post-Processing Pipeline**: Integrated hardware Activation (ReLU), Quantization (8-bit downshift), and a 2x2 Max Pooling unit.
- **Parametrizable**: Easily adjustable `N`, `DATA_WIDTH`, and `ACC_WIDTH` natively through standard module parameters in `npu_top.v`.
- **Verified**: Fully tested using Cocotb + Verilator, with 100% functional testbench coverage.

---

<div align="center">
  <h2>Interfaces</h2>
</div>

| Interface | Type | Description |
|-----------|------|-------------|
| `cmd_in` | 32-bit Command | Hardware FIFO interface for pushing encoded configuration and layer execution commands. |
| `ibuf_*` | SRAM Write | Exposes the internal Activation Buffer (IBUF) for DMA/CPU preloading. |
| `wbuf_*` | SRAM Write | Exposes the internal Weight Buffer (WBUF) for DMA/CPU preloading. |
| `pbuf_*` | SRAM Write | Exposes the 32-bit Partial Sum Accumulator (PBUF) for preloading biases. |
| `obuf_*` | SRAM Read | Exposes the final Output Buffer (OBUF) containing the post-processed result matrix. |

---

<div align="center">
  <h2>Quick Start</h2>
</div>

1. Stream the model's weights and input activations into the `wbuf` and `ibuf` SRAM interfaces respectively.
2. Push a sequence of commands (e.g. `OP_LOAD_WEIGHTS`, `OP_RUN_MAC`) into the `cmd_in` FIFO.
3. The internal `layer_controller` automatically pulls the data, skews it, runs it through the systolic grid, and accumulates it.
4. Read the resulting matrix directly from the `obuf_rd_data` interface!

---

<div align="center">
  <h2>Directory Structure</h2>
</div>

- `rtl/npu_top.v` : The main subsystem wrapper (connects control, SRAMs, and systolic array).
- `rtl/layer_controller.v` : Translates FIFO commands into exact cycle-level pipeline control.
- `rtl/sram_buffers.v` : Synthesizable wrappers for IBUF, WBUF, and OBUF memories.
- `rtl/accumulator_pbuf.v` : 32-bit partial sum accumulator for deep channel accumulation.
- `rtl/activation_pool.v` & `rtl/max_pool_2x2.v` : Post-processing pipeline.
- `rtl/systolic_array.v` & `rtl/pe.v` : The core matrix multiplication grid.
- `rtl/skew_buffers.v` : Hardware input skewing and output unskewing pipeline.
- `tb/test_npu.py` : Comprehensive Cocotb UVM-like testbench.
- `tb/Makefile` : Makefile to run the simulation (Verilator + Coverage enabled by default).

---

<div align="center">
  <h2>The Testbench Features</h2>
</div>

The Cocotb testbench located at `tb/test_npu.py` is written as an all-in-one comprehensive verification suite:
1. **UVM-like Architecture**: Separated into memory-mapped drivers, monitors, and a golden scoreboard.
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
