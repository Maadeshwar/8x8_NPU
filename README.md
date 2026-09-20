<h1 align="center">Configurable Neural Processing Unit (NPU)</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Architecture-Systolic_Array-FF3366?style=for-the-badge" alt="Architecture">
  <img src="https://img.shields.io/badge/Topology-Output_Stationary-007ACC?style=for-the-badge" alt="Topology">
  <img src="https://img.shields.io/badge/Precision-INT8_Weights_%2F_Activations-9C27B0?style=for-the-badge" alt="INT8">
  <img src="https://img.shields.io/badge/Accumulator-INT32_Partial_Sums-4B32C3?style=for-the-badge" alt="INT32">
  <img src="https://img.shields.io/badge/Activation-Hardware_ReLU-FF9900?style=for-the-badge" alt="ReLU">
  <img src="https://img.shields.io/badge/Downsampling-2x2_Max_Pool-E91E63?style=for-the-badge" alt="Pooling">
</p>

---

## Architectural Block Diagram

The datapath completely isolates memory routing from the computational core, ensuring zero-stall execution during processing phases.

```mermaid
flowchart TD
    subgraph Memory [Memory Mapped SRAMs]
        IBUF[(IBUF<br>Input)]
        WBUF[(WBUF<br>Weights)]
        PBUF[(PBUF<br>Bias / Psums)]
        OBUF[(OBUF<br>Output)]
        CMD[(Command<br>FIFO)]
    end

    subgraph Control [Control Logic]
        FSM{3-Stage FSM<br>Layer Controller}
    end

    subgraph Compute [Datapath]
        SYS[NxN Systolic Array]
        RELU[Hardware ReLU]
        POOL[2x2 Max Pool]
        QUANT[Quantization]
    end

    CMD --> FSM
    IBUF & WBUF --> SYS
    FSM -->|Addresses & Enables| Memory
    FSM -->|Pipeline Sync| Compute
    SYS <--> PBUF
    SYS --> QUANT --> RELU --> POOL --> OBUF
```

## RTL Structural Design

The repository follows strict, production-grade structural Verilog constraints to guarantee timing closure and maintainability.

### 1. The 3-Stage (3-Block) FSM
The `layer_controller.v` is explicitly engineered using the industry-standard **3-Stage FSM architecture**. This prevents combinational glitches and isolates state tracking from output logic.

```verilog
// STAGE 1: Sequential State Update
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_IDLE;
    else state <= next_state;
end

// STAGE 2: Combinational Next-State Logic
always @(*) begin
    next_state = state; // Default hold
    case (state)
        S_IDLE: if (cmd_valid) next_state = S_LOAD;
        S_LOAD: if (load_done) next_state = S_IDLE;
        // ... state routing logic
    endcase
end

// STAGE 3: Registered Output Logic
always @(posedge clk or negedge rst_n) begin
    // Drives SRAM read addresses and array enables synchronously
end
```

### 2. Module Hierarchy
The logic is cleanly modularized. `npu_top.v` orchestrates the entire flow without legacy wrappers:
* `npu_top.v`
  * `layer_controller.v` (3-Stage FSM)
  * `sram_buffers.v` (IBUF, WBUF, OBUF)
  * `accumulator_pbuf.v` (Bias Addition)
  * `systolic_array.v` (NxN MAC Engine)
    * `pe.v` (Processing Elements)
  * `activation_pool.v` (ReLU & Pooling)

## Core Features

* **Parameterized Scale:** Scale the physical matrix size simply by overriding `parameter N`. No internal logic changes required.
* **Native Bias (A*B + C):** CPU pre-loads bias vectors into the PBUF. The hardware automatically fetches and accumulates them during execution.
* **Zero-Protocol Interface:** Abstracted `addr`, `data`, `we` ports bypass the heavy latency of internal AXI/Avalon wrappers, allowing seamless SoC integration.

## Verification

Verified via Python/Cocotb against Numpy Golden Models asserting 100% bit-accuracy on extreme edge cases: 
* Identity Matrices & Zeros
* Accumulator Saturation (Maximum Values)
* ReLU integer clipping
* 2x2 Spatial Pool Isolation
