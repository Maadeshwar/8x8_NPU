<div align="center">

# Parameterized NxN NPU

<img src="https://img.shields.io/badge/Hardware-Verilog-blue?style=for-the-badge" alt="Verilog" />
<img src="https://img.shields.io/badge/Architecture-Systolic%20Array-blueviolet?style=for-the-badge" alt="Systolic Array" />
<img src="https://img.shields.io/badge/Dataflow-Weight%20Stationary-ff69b4?style=for-the-badge" alt="Weight Stationary" />
<img src="https://img.shields.io/badge/Precision-INT8%2FINT32-orange?style=for-the-badge" alt="INT8/INT32" />
<img src="https://img.shields.io/badge/Status-Verified-success?style=for-the-badge" alt="Verified" />

<br/>

<p align="center">
A parameterized Weight-Stationary Systolic Array NPU written in Verilog, optimized for matrix multiplication.<br/>
By default, this is an 8x8 NPU processing INT8 activations and weights, and outputting INT32 partial sums.
</p>

</div>

---

<div align="center">
  <h2>Features</h2>
</div>

- **Fully Parameterized**: Easily adjust the array size (`N`), `DATA_WIDTH`, and `ACC_WIDTH` at instantiation.
- **Weight-Stationary Dataflow**: The standard, highly efficient architecture for CNNs and Matrix Multiplication.
- **Glitch-Free FSM**: A clean 3-stage FSM (`IDLE`, `LOAD_WEIGHTS`, `MAC_STREAM`) controls the core without combinatorial loops or glitches.
- **Clean Resets**: Synchronous active-low reset (`rst_n`) rigorously applied to all registers.
- **Strict Linting**: Compliant with `verilator --lint-only -Wall` to ensure zero errors and zero warnings.

---

<div align="center">
  <h2>Directory Structure</h2>
</div>

- `rtl/pe.v` : Processing Element (MAC + Weight Register).
- `rtl/systolic_array.v` : Generates the NxN array of PEs.
- `rtl/npu_core.v` : The top module, containing the FSM and structural wiring.
- `tb/test_npu.py` : Comprehensive Cocotb UVM-like testbench.
- `tb/Makefile` : Makefile to run the simulation (Verilator + Coverage enabled by default).
- `lint.sh` : Script to run the linter.

---

<div align="center">
  <h2>The Testbench Features</h2>
</div>

The Cocotb testbench located at `tb/test_npu.py` is written as an all-in-one comprehensive verification suite:
1. **UVM-like Architecture**: Separated into `NpuDriver` (stimulus), `NpuMonitor` (observation), and `NpuScoreboard` (golden model comparison).
2. **Regression Suite**: Contains multiple decorators that run automatically in sequence.
3. **Directed Tests**: Tests `Identity`, `Zeros`, and `Max Values` matrices to catch edge cases, in addition to purely random matrices.
4. **Code Coverage**: The `Makefile` enables `verilator --coverage` to track line, toggle, and structural coverage in the RTL.
5. **Functional Coverage**: Uses `cocotb_coverage` to track configuration metrics and ensuring all directed test cases are hit.

---

<div align="center">
  <h2>Running the Verification</h2>
</div>

To run the full regression testbench and generate coverage:

```bash
cd tb
make
```

To run the strict RTL linting:

```bash
./lint.sh
```

*(Note: If you are on Windows, you can run Verilator via WSL using `wsl verilator --lint-only -Wall rtl/*.v`)*


