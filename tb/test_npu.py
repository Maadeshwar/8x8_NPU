import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, Combine
import numpy as np
import os

try:
    from cocotb_coverage.coverage import CoverPoint, coverage_db
except ImportError:
    cocotb.log.warning("cocotb-coverage not installed. Functional coverage will be disabled.")
    def CoverPoint(*args, **kwargs):
        def decorator(func):
            return func
        return decorator
    class MockDB:
        def export_to_xml(self, *args, **kwargs): pass
    coverage_db = MockDB()

# -------------------------------------------------------------------
# Functional Coverage Definitions
# -------------------------------------------------------------------
# Track which configurations and test types we hit during the regression
@CoverPoint("top.npu_core.N", xf=lambda params: params['N'], bins=[4, 8, 16, 32, 64])
@CoverPoint("top.npu_core.test_type", xf=lambda params: params['test_type'], bins=["random", "directed_identity", "directed_zeros", "directed_max", "directed_checkerboard"])
def sample_test_coverage(params):
    pass

# -------------------------------------------------------------------
# UVM-like Base Components
# -------------------------------------------------------------------
class NpuDriver:
    """Drives inputs to the NPU"""
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk
        self.N = int(dut.N.value)
        self.DATA_WIDTH = int(dut.DATA_WIDTH.value)

    async def reset(self):
        self.dut.rst_n.value = 0
        self.dut.start_load.value = 0
        self.dut.start_mac.value = 0
        self.dut.weight_in.value = 0
        self.dut.act_in.value = 0
        self.dut.psum_in.value = 0
        await Timer(20, units="ns")
        self.dut.rst_n.value = 1
        await RisingEdge(self.clk)

    async def load_weights(self, W):
        self.dut.start_load.value = 1
        await RisingEdge(self.clk)
        self.dut.start_load.value = 0
        
        for i in range(self.N):
            row_data = W[self.N - 1 - i, :]
            val = 0
            for j in range(self.N):
                mask = (1 << self.DATA_WIDTH) - 1
                val |= (int(row_data[j]) & mask) << (j * self.DATA_WIDTH)
            self.dut.weight_in.value = val
            await RisingEdge(self.clk)
            
        self.dut.weight_in.value = 0
        while self.dut.ready.value == 0:
            await RisingEdge(self.clk)

    async def stream_activations(self, A):
        self.dut.start_mac.value = 1
        self.dut.psum_in.value = 0
        total_cycles = 3 * self.N
        
        for cycle in range(total_cycles):
            val = 0
            for i in range(self.N):
                j = cycle - i
                if 0 <= j < self.N:
                    act_val = A[j, i]
                else:
                    act_val = 0
                mask = (1 << self.DATA_WIDTH) - 1
                val |= (int(act_val) & mask) << (i * self.DATA_WIDTH)
            self.dut.act_in.value = val
            await RisingEdge(self.clk)
            
        self.dut.start_mac.value = 0

class NpuMonitor:
    """Monitors outputs from the NPU"""
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk
        self.N = int(dut.N.value)
        self.actual_out = np.zeros((self.N, self.N), dtype=np.int32)

    async def monitor_output(self):
        total_cycles = 3 * self.N
        for cycle in range(total_cycles):
            out_val = self.dut.psum_out.value
            if out_val.is_resolvable:
                out_int = int(out_val)
                for j in range(self.N):
                    # Adjusting index mapping by -1 to account for 1 cycle PE output delay
                    i_calc = cycle - j - self.N - 1
                    if 0 <= i_calc < self.N:
                        mask = 0xFFFFFFFF
                        res = (out_int >> (j * 32)) & mask
                        # Sign extension for INT32
                        if res & 0x80000000:
                            res -= 0x100000000
                        self.actual_out[i_calc, j] = res
            await RisingEdge(self.clk)

class NpuScoreboard:
    """Compares monitored output with Golden Model (NumPy)"""
    def __init__(self, N):
        self.N = N

    def check(self, expected, actual):
        if np.array_equal(expected, actual):
            cocotb.log.info("SCOREBOARD: PASS - Actual output perfectly matches golden model.")
        else:
            cocotb.log.error(f"SCOREBOARD: FAIL - Matrix mismatch!\nExpected:\n{expected}\nActual:\n{actual}")
            assert False, "Scoreboard mismatch"

# -------------------------------------------------------------------
# Test Environment (Agent)
# -------------------------------------------------------------------
async def npu_env(dut, W, A, test_type="random"):
    """Top level environment coordinating the UVM-like components"""
    N = int(dut.N.value)
    
    # 1. Sample Functional Coverage
    sample_test_coverage({"N": N, "test_type": test_type})
    
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = NpuDriver(dut, dut.clk)
    monitor = NpuMonitor(dut, dut.clk)
    scoreboard = NpuScoreboard(N)
    
    # 2. Golden Model
    expected_out = np.dot(A.astype(np.int32), W.astype(np.int32))
    
    # 3. Stimulus
    await driver.reset()
    await driver.load_weights(W)
    
    # 4. Concurrently run driver and monitor
    drive_task = cocotb.start_soon(driver.stream_activations(A))
    monitor_task = cocotb.start_soon(monitor.monitor_output())
    
    await Combine(drive_task, monitor_task)
    
    # 5. Scoreboard Check
    scoreboard.check(expected_out, monitor.actual_out)

# -------------------------------------------------------------------
# Test Cases (Regression Suite)
# -------------------------------------------------------------------

@cocotb.test()
async def test_random(dut):
    """Random Matrix Multiplication Test"""
    N = int(dut.N.value)
    W = np.random.randint(-128, 127, size=(N, N), dtype=np.int8)
    A = np.random.randint(-128, 127, size=(N, N), dtype=np.int8)
    await npu_env(dut, W, A, test_type="random")

@cocotb.test()
async def test_identity(dut):
    """Directed Test: Identity Matrix"""
    N = int(dut.N.value)
    W = np.eye(N, dtype=np.int8)
    A = np.random.randint(-128, 127, size=(N, N), dtype=np.int8)
    await npu_env(dut, W, A, test_type="directed_identity")

@cocotb.test()
async def test_zeros(dut):
    """Directed Test: Zeros Matrix (No propagation)"""
    N = int(dut.N.value)
    W = np.zeros((N, N), dtype=np.int8)
    A = np.random.randint(-128, 127, size=(N, N), dtype=np.int8)
    await npu_env(dut, W, A, test_type="directed_zeros")

@cocotb.test()
async def test_max_values(dut):
    """Directed Test: Max Positive/Negative Boundaries"""
    N = int(dut.N.value)
    W = np.full((N, N), 127, dtype=np.int8)
    A = np.full((N, N), -128, dtype=np.int8)
    await npu_env(dut, W, A, test_type="directed_max")

@cocotb.test()
async def test_checkerboard(dut):
    """Directed Test: Alternating Checkboard Matrix"""
    N = int(dut.N.value)
    # Create checkerboard pattern
    W = np.fromfunction(lambda i, j: (i + j) % 2, (N, N)).astype(np.int8) * 127
    A = np.fromfunction(lambda i, j: (i + j + 1) % 2, (N, N)).astype(np.int8) * 127
    await npu_env(dut, W, A, test_type="directed_checkerboard")

@cocotb.test()
async def coverage_report(dut):
    """Generate the Coverage report after all tests."""
    # Simply running an empty test to export coverage db
    coverage_db.export_to_xml(filename="coverage.xml")
    cocotb.log.info("Functional Coverage report generated (coverage.xml)")
