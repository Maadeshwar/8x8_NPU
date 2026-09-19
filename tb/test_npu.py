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
@CoverPoint("top.axis_npu.N", xf=lambda params: params['N'], bins=[4, 8, 16, 32, 64])
@CoverPoint("top.axis_npu.test_type", xf=lambda params: params['test_type'], bins=["random", "directed_identity", "directed_zeros", "directed_max", "directed_checkerboard"])
def sample_test_coverage(params):
    pass

# -------------------------------------------------------------------
# UVM-like Base Components
# -------------------------------------------------------------------
class NpuDriver:
    """Drives AXI4-Stream inputs to the NPU"""
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk
        self.N = int(dut.N.value)
        self.DATA_WIDTH = int(dut.DATA_WIDTH.value)

    async def reset(self):
        self.dut.rst_n.value = 0
        self.dut.s_axis_w_tvalid.value = 0
        self.dut.s_axis_a_tvalid.value = 0
        self.dut.m_axis_out_tready.value = 1
        await Timer(20, units="ns")
        self.dut.rst_n.value = 1
        await RisingEdge(self.clk)

    async def load_weights(self, W):
        for i in range(self.N):
            row_data = W[self.N - 1 - i, :]
            val = 0
            for j in range(self.N):
                mask = (1 << self.DATA_WIDTH) - 1
                val |= (int(row_data[j]) & mask) << (j * self.DATA_WIDTH)
            self.dut.s_axis_w_tdata.value = val
            self.dut.s_axis_w_tvalid.value = 1
            if i == self.N - 1:
                self.dut.s_axis_w_tlast.value = 1
            else:
                self.dut.s_axis_w_tlast.value = 0
                
            await RisingEdge(self.clk)
            while self.dut.s_axis_w_tready.value == 0:
                await RisingEdge(self.clk)
                
        self.dut.s_axis_w_tvalid.value = 0
        self.dut.s_axis_w_tlast.value = 0

    async def stream_activations(self, A):
        for i in range(self.N):
            row_data = A[i, :]
            val = 0
            for j in range(self.N):
                mask = (1 << self.DATA_WIDTH) - 1
                val |= (int(row_data[j]) & mask) << (j * self.DATA_WIDTH)
            self.dut.s_axis_a_tdata.value = val
            self.dut.s_axis_a_tvalid.value = 1
            if i == self.N - 1:
                self.dut.s_axis_a_tlast.value = 1
            else:
                self.dut.s_axis_a_tlast.value = 0
                
            await RisingEdge(self.clk)
            while self.dut.s_axis_a_tready.value == 0:
                await RisingEdge(self.clk)
                
        self.dut.s_axis_a_tvalid.value = 0
        self.dut.s_axis_a_tlast.value = 0

class NpuMonitor:
    """Monitors AXI4-Stream outputs from the NPU"""
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk
        self.N = int(dut.N.value)
        self.actual_out = np.zeros((self.N, self.N), dtype=np.int32)
        self.row_idx = 0

    async def monitor_output(self):
        self.dut.m_axis_out_tready.value = 1
        
        while self.row_idx < self.N:
            await RisingEdge(self.clk)
            if self.dut.m_axis_out_tvalid.value == 1 and self.dut.m_axis_out_tready.value == 1:
                out_val = self.dut.m_axis_out_tdata.value
                if out_val.is_resolvable:
                    out_int = int(out_val)
                    for j in range(self.N):
                        mask = 0xFFFFFFFF
                        res = (out_int >> (j * 32)) & mask
                        # Sign extension for INT32
                        if res & 0x80000000:
                            res -= 0x100000000
                        self.actual_out[self.row_idx, j] = res
                    self.row_idx += 1
                    
                    if self.dut.m_axis_out_tlast.value == 1:
                        break

class NpuScoreboard:
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
    N = int(dut.N.value)
    
    sample_test_coverage({"N": N, "test_type": test_type})
    
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = NpuDriver(dut, dut.clk)
    monitor = NpuMonitor(dut, dut.clk)
    scoreboard = NpuScoreboard(N)
    
    expected_out = np.dot(A.astype(np.int32), W.astype(np.int32))
    
    await driver.reset()
    await driver.load_weights(W)
    
    drive_task = cocotb.start_soon(driver.stream_activations(A))
    monitor_task = cocotb.start_soon(monitor.monitor_output())
    
    await Combine(drive_task, monitor_task)
    
    scoreboard.check(expected_out, monitor.actual_out)

# -------------------------------------------------------------------
# Test Cases (Regression Suite)
# -------------------------------------------------------------------

@cocotb.test()
async def test_random(dut):
    N = int(dut.N.value)
    W = np.random.randint(-128, 127, size=(N, N), dtype=np.int8)
    A = np.random.randint(-128, 127, size=(N, N), dtype=np.int8)
    await npu_env(dut, W, A, test_type="random")

@cocotb.test()
async def test_identity(dut):
    N = int(dut.N.value)
    W = np.eye(N, dtype=np.int8)
    A = np.random.randint(-128, 127, size=(N, N), dtype=np.int8)
    await npu_env(dut, W, A, test_type="directed_identity")

@cocotb.test()
async def test_zeros(dut):
    N = int(dut.N.value)
    W = np.zeros((N, N), dtype=np.int8)
    A = np.random.randint(-128, 127, size=(N, N), dtype=np.int8)
    await npu_env(dut, W, A, test_type="directed_zeros")

@cocotb.test()
async def test_max_values(dut):
    N = int(dut.N.value)
    W = np.full((N, N), 127, dtype=np.int8)
    A = np.full((N, N), -128, dtype=np.int8)
    await npu_env(dut, W, A, test_type="directed_max")

@cocotb.test()
async def test_checkerboard(dut):
    N = int(dut.N.value)
    W = np.fromfunction(lambda i, j: (i + j) % 2, (N, N)).astype(np.int8) * 127
    A = np.fromfunction(lambda i, j: (i + j + 1) % 2, (N, N)).astype(np.int8) * 127
    await npu_env(dut, W, A, test_type="directed_checkerboard")

@cocotb.test()
async def coverage_report(dut):
    coverage_db.export_to_xml(filename="coverage.xml")
    cocotb.log.info("Functional Coverage report generated (coverage.xml)")
