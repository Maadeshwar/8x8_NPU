<h1 align="center">Configurable Neural Processing Unit (NPU)</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Language-Verilog_2001-007ACC?style=for-the-badge" alt="Verilog">
  <img src="https://img.shields.io/badge/Architecture-Systolic_Array-FF3366?style=for-the-badge" alt="Architecture">
  <img src="https://img.shields.io/badge/Integration-Memory_Mapped-9C27B0?style=for-the-badge" alt="Memory Mapped">
  <img src="https://img.shields.io/badge/Verification-Cocotb_%26_Verilator-4B32C3?style=for-the-badge" alt="Verification">
  <img src="https://img.shields.io/badge/Status-Production_Grade-00C853?style=for-the-badge" alt="Status">
</p>

---

<h2 align="center">Architectural Overview</h2>

This repository contains a high-performance, fully parameterized, production-grade Neural Processing Unit (NPU). The architecture is engineered around a highly scalable NxN Systolic Array capable of natively executing complete Convolutional Neural Network (CNN) layers, including matrix multiplication, bias addition, non-linear activation, and spatial downsampling, entirely in a single hardware pass.

Designed for seamless System-on-Chip (SoC) integration, the NPU completely abstracts the complex timing constraints of systolic data skewing and unskewing behind a localized, autonomous controller and standard memory-mapped SRAM interfaces.

---

<h2 align="center">Core Subsystems and Features</h2>

<h3 align="center">1. Parameterized Systolic Math Engine</h3>
The mathematical core of the NPU is a highly optimized, output-stationary Systolic Array. 
* **Universal Scalability:** The array size is driven by a top-level parameter N. Instantiating the module as a lightweight 8x8 edge accelerator or a massive 32x32 datacenter engine requires zero code rewrites. 
* **Data Width Flexibility:** Features configurable DATA_WIDTH (default 8-bit integer) and ACC_WIDTH (default 32-bit internal accumulator) for precision control during inference.

<h3 align="center">2. The 3-Stage FSM Layer Controller</h3>
At the heart of the NPU's intelligence lies a rigorous, zero-overhead **3-Stage Finite State Machine (FSM)**. This controller replaces legacy hardware wrappers by directly orchestrating internal SRAM reads, array enablement, and pipeline alignment.
* **Stage 0 [IDLE]:** The controller rests in a low-power state, continuously polling the asynchronous Command FIFO. During this stage, the external CPU or DMA has uncontested write access to the memory buffers.
* **Stage 1 [LOAD_WEIGHT]:** Upon receiving an OP_LOAD_WEIGHTS command, the FSM autonomously generates sequential read addresses for the Weight Buffer (WBUF), streaming the kernel data directly into the physical Processing Elements (PEs) of the systolic array to lock the weights in place.
* **Stage 2 [RUN_MAC]:** Triggered by an OP_RUN_MAC command, the FSM enters the execution state. It coordinates the reading of Input Activations (IBUF), manages the latency of the data skewing buffers, drives the partial sum accumulation, and triggers the write-back process to the Output Buffer (OBUF).

<h3 align="center">3. Native Hardware Post-Processing</h3>
Instead of relying on the CPU to perform post-processing on raw matrix multiplication outputs, the NPU pipeline natively integrates highly optimized post-processing modules.
* **Bias Addition:** The Partial Sum Buffer (PBUF) exposes a CPU write interface, allowing bias vectors to be pre-loaded into memory. During the RUN_MAC stage, the hardware simultaneously fetches the bias and accumulates it with the incoming matrix dot-product.
* **Activation:** A dedicated inline module computes **ReLU** (Rectified Linear Unit) activation, instantly clamping negative partial sums to zero.
* **Downsampling:** A dedicated **2x2 Max Pooling** module physically captures consecutive matrix rows, multiplexes the highest values, and downsamples the output resolution in real-time before writing to the OBUF.
* **Quantization Scaling:** An integrated barrel shifter truncates the 32-bit accumulated output back down to 8-bit representations, allowing for int8 Post-Training Quantization (PTQ) compatibility.

---

<h2 align="center">Memory Hierarchy and Integration</h2>

The NPU eliminates the requirement for heavy proprietary bus wrappers (like AXI4 or Avalon) internally. Instead, it utilizes standard, universally understood SRAM pinouts (addr, data, we), making it effortlessly compatible with any system architecture.

<h3 align="center">Buffer Architecture</h3>

* **IBUF (Input Buffer):** Stores the input activation tensors. For Convolutional layers, software flattens the image using im2col before transferring to IBUF.
* **WBUF (Weight Buffer):** Stores the dense weight matrices or flattened convolutional kernels.
* **PBUF (Partial Sum Buffer):** A deep 32-bit memory buffer used to store multi-pass Matrix Tiling intermediate results, or to preload Bias vectors.
* **OBUF (Output Buffer):** A read-only buffer containing the final processed tensors for the CPU to read back.
* **Command FIFO:** An asynchronous 32-bit ring buffer where the CPU pushes operational opcodes.

<h3 align="center">Command Packet Structure</h3>

The CPU controls the NPU by pushing 32-bit packets into the Command FIFO.
* [31:28] - **Opcode:** 1 (Load Weights), 2 (Run MAC), 3 (Set Tiler)
* [27:0]  - **Payload:** For RUN_MAC, the payload dictates execution parameters:
  * [27] - **Accumulate Enable:** If high, adds the contents of PBUF to the array output (used for Bias or Tiling).
  * [26] - **Finish Pass:** If high, routes the output through Quantization, ReLU, and Pooling before writing to OBUF.
  * [25:0] - **Cycles:** The number of rows to process in the current execution block.

---

<h2 align="center">Verification Rigor</h2>

To guarantee mathematical perfection and production-grade stability, this NPU is verified via a state-of-the-art **Python/Cocotb** framework running on the **Verilator** cycle-accurate simulator.

<h3 align="center">Automated Testbench Coverage</h3>
Every physical hardware pass is dynamically compared against a custom Python numpy Golden Model. The automated suite asserts 100% bit-accurate matching across a gauntlet of extreme edge cases:
1. **Identity Matrices:** Verifies baseline matrix-vector alignment.
2. **Zeros:** Verifies truncation and reset states.
3. **Randomized Data:** Verifies standard dot-product functionality.
4. **Checkerboard Patterns:** Verifies alternating bit-flip stability.
5. **Maximum Values:** Verifies accumulator overflow resistance and saturation.
6. **ReLU Assertions:** Verifies negative integer clamping.
7. **Quantization Precision:** Verifies dynamic bit-shifting math.
8. **Max Pooling Isolation:** Verifies spatial 2x2 comparison logic.

---

<h2 align="center">Repository File Structure</h2>

* /rtl/ - The pure Verilog-2001 source files for the NPU. npu_top.v is the highest-level module.
* /tb/ - The Cocotb Python verification environment, Golden Models, and Makefile.
