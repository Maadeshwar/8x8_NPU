import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import numpy as np

OP_LOAD_WEIGHTS = 1
OP_RUN_MAC      = 2
OP_SET_TILER    = 3

class NpuDriver:
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk
        self.N = int(dut.N.value)
        self.DATA_WIDTH = int(dut.DATA_WIDTH.value)
        self.ACC_WIDTH = int(dut.ACC_WIDTH.value)

    async def reset(self):
        self.dut.rst_n.value = 0
        self.dut.cmd_push.value = 0
        self.dut.ibuf_we.value = 0
        self.dut.wbuf_we.value = 0
        self.dut.pbuf_we.value = 0
        self.dut.quant_shift.value = 0
        self.dut.relu_en.value = 0
        self.dut.pool_en.value = 0
        await Timer(20, units='ns')
        self.dut.rst_n.value = 1
        await RisingEdge(self.clk)

    async def write_wbuf(self, addr, data):
        self.dut.wbuf_wr_addr.value = addr
        self.dut.wbuf_wr_data.value = data
        self.dut.wbuf_we.value = 1
        await RisingEdge(self.clk)
        self.dut.wbuf_we.value = 0

    async def write_ibuf(self, addr, data):
        self.dut.ibuf_wr_addr.value = addr
        self.dut.ibuf_wr_data.value = data
        self.dut.ibuf_we.value = 1
        await RisingEdge(self.clk)
        self.dut.ibuf_we.value = 0

    async def push_cmd(self, opcode, payload):
        while self.dut.cmd_full.value == 1:
            await RisingEdge(self.clk)
        self.dut.cmd_in.value = (opcode << 28) | (payload & 0x0FFFFFFF)
        self.dut.cmd_push.value = 1
        await RisingEdge(self.clk)
        self.dut.cmd_push.value = 0

    async def read_obuf(self, addr):
        self.dut.obuf_rd_addr.value = addr
        await RisingEdge(self.clk)
        await RisingEdge(self.clk) # 1 cycle read latency
        return self.dut.obuf_rd_data.value

async def run_npu_test(dut, W, A):
    clock = Clock(dut.clk, 10, units='ns')
    cocotb.start_soon(clock.start())
    
    driver = NpuDriver(dut, dut.clk)
    await driver.reset()
    
    # 1. Load WBUF (Weights)
    for i in range(driver.N):
        row_data = W[driver.N - 1 - i, :]
        val = 0
        for j in range(driver.N):
            mask = (1 << driver.DATA_WIDTH) - 1
            val |= (int(row_data[j]) & mask) << (j * driver.DATA_WIDTH)
        await driver.write_wbuf(i, val)

    # 2. Load IBUF (Activations)
    for i in range(driver.N):
        row_data = A[i, :]
        val = 0
        for j in range(driver.N):
            mask = (1 << driver.DATA_WIDTH) - 1
            val |= (int(row_data[j]) & mask) << (j * driver.DATA_WIDTH)
        await driver.write_ibuf(i, val)
        
    # 3. Configure
    dut.quant_shift.value = 0
    dut.relu_en.value = 0
    dut.pool_en.value = 0
    
    # 4. Commands
    await driver.push_cmd(OP_LOAD_WEIGHTS, driver.N)
    await driver.push_cmd(OP_SET_TILER, 0)
    
    run_payload = (0 << 27) | (1 << 26) | driver.N
    await driver.push_cmd(OP_RUN_MAC, run_payload)
    
    # Wait for execution
    for _ in range(50 + driver.N * 3):
        await RisingEdge(dut.clk)
        
    # 5. Read OBUF
    actual_out = np.zeros((driver.N, driver.N), dtype=np.int32)
    for i in range(driver.N):
        out_val = await driver.read_obuf(i)
        if out_val.is_resolvable:
            out_int = int(out_val)
            for j in range(driver.N):
                mask = 0xFF
                res = (out_int >> (j * 8)) & mask
                if res & 0x80:
                    res -= 0x100
                actual_out[i, j] = res

    expected_out = np.dot(A.astype(np.int32), W.astype(np.int32))
    expected_out = np.clip(expected_out, -128, 127)
    
    if np.array_equal(expected_out, actual_out):
        cocotb.log.info('SCOREBOARD: PASS - Actual output perfectly matches golden model.')
    else:
        cocotb.log.error(f'SCOREBOARD: FAIL - Matrix mismatch!\nExpected:\n{expected_out}\nActual:\n{actual_out}')
        assert False, 'Scoreboard mismatch'

@cocotb.test()
async def test_identity(dut):
    N = int(dut.N.value)
    W = np.eye(N, dtype=np.int8)
    A = np.random.randint(-10, 10, size=(N, N), dtype=np.int8)
    await run_npu_test(dut, W, A)

@cocotb.test()
async def test_random(dut):
    N = int(dut.N.value)
    W = np.random.randint(-128, 127, size=(N, N), dtype=np.int8)
    A = np.random.randint(-128, 127, size=(N, N), dtype=np.int8)
    await run_npu_test(dut, W, A)

@cocotb.test()
async def test_zeros(dut):
    N = int(dut.N.value)
    W = np.zeros((N, N), dtype=np.int8)
    A = np.random.randint(-128, 127, size=(N, N), dtype=np.int8)
    await run_npu_test(dut, W, A)

@cocotb.test()
async def test_max_values(dut):
    N = int(dut.N.value)
    W = np.full((N, N), 127, dtype=np.int8)
    A = np.full((N, N), -128, dtype=np.int8)
    await run_npu_test(dut, W, A)

@cocotb.test()
async def test_checkerboard(dut):
    N = int(dut.N.value)
    W = np.fromfunction(lambda i, j: (i + j) % 2, (N, N)).astype(np.int8) * 127
    A = np.fromfunction(lambda i, j: (i + j + 1) % 2, (N, N)).astype(np.int8) * 127
    await run_npu_test(dut, W, A)
