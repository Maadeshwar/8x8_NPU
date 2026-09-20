/* verilator lint_off SYNCASYNCNET */
/* verilator lint_off UNUSEDSIGNAL */
`default_nettype none

module npu_top #(
    parameter N = 8,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32,
    parameter FIFO_DEPTH_LOG2 = 4,
    parameter IBUF_DEPTH = 1024,
    parameter WBUF_DEPTH = 1024,
    parameter OBUF_DEPTH = 1024
)(
    input  wire clk,
    input  wire rst_n,
    
    // CPU Command interface
    input  wire [31:0] cmd_in,
    input  wire        cmd_push,
    output wire        cmd_full,
    
    // CPU/DMA Memory Interface (Simplified)
    input  wire [$clog2(IBUF_DEPTH)-1:0] ibuf_wr_addr,
    input  wire [N*DATA_WIDTH-1:0]       ibuf_wr_data,
    input  wire                          ibuf_we,

    input  wire [$clog2(WBUF_DEPTH)-1:0] wbuf_wr_addr,
    input  wire [N*DATA_WIDTH-1:0]       wbuf_wr_data,
    input  wire                          wbuf_we,

    input  wire [$clog2(OBUF_DEPTH)-1:0] obuf_rd_addr,
    output wire [N*DATA_WIDTH-1:0]       obuf_rd_data,
    
    input  wire [$clog2(OBUF_DEPTH)-1:0] pbuf_wr_addr,
    input  wire [N*ACC_WIDTH-1:0]        pbuf_wr_data,
    input  wire                          pbuf_we,
    
    // Config
    input  wire [4:0] quant_shift,
    input  wire       relu_en,
    input  wire       pool_en
);

    // Interconnect wires
    wire [31:0] cmd_data;
    wire cmd_empty, cmd_pop;
    
    wire [$clog2(IBUF_DEPTH)-1:0] ibuf_rd_addr;
    wire [$clog2(WBUF_DEPTH)-1:0] wbuf_rd_addr;
    wire [$clog2(OBUF_DEPTH)-1:0] obuf_wr_addr;
    wire obuf_we;
    
    wire [N*DATA_WIDTH-1:0] ibuf_rd_data;
    wire [N*DATA_WIDTH-1:0] wbuf_rd_data;
    wire [N*DATA_WIDTH-1:0] obuf_wr_data;
    
    wire npu_start_load, npu_start_mac;
    wire npu_ready = 1'b1;
    wire skew_en, skew_w_en;
    
    wire [N*DATA_WIDTH-1:0] skewed_act;
    wire [N*DATA_WIDTH-1:0] w_delay; // Just pipeline stage
    
    wire [N*ACC_WIDTH-1:0] npu_psum_out;
    
    wire [N*ACC_WIDTH-1:0] unskewed_psum;
    wire unskew_valid;
    
    wire act_valid_out; 
    wire [N*DATA_WIDTH-1:0] act_data_out;
    
    wire pool_valid_out;
    wire [(N/2)*DATA_WIDTH-1:0] pool_data_out;
    
    // 1. Command FIFO
    npu_command_fifo #(
        .DATA_WIDTH(32),
        .DEPTH_LOG2(FIFO_DEPTH_LOG2)
    ) i_cmd_fifo (
        .clk(clk), .rst_n(rst_n),
        .push(cmd_push), .data_in(cmd_in), .full(cmd_full),
        .pop(cmd_pop), .data_out(cmd_data), .empty(cmd_empty)
    );
    
    // 2. SRAM Buffers
    // Use pool_valid_out for writing to OBUF. Pack the pooled data into the lower half.
    wire obuf_write_en = pool_en ? pool_valid_out : act_valid_out;
    wire [N*DATA_WIDTH-1:0] final_obuf_data = pool_en ? { {(N/2*DATA_WIDTH){1'b0}}, pool_data_out } : act_data_out;
    
    sram_buffers #(
        .N(N), .DATA_WIDTH(DATA_WIDTH),
        .IBUF_DEPTH(IBUF_DEPTH), .WBUF_DEPTH(WBUF_DEPTH), .OBUF_DEPTH(OBUF_DEPTH)
    ) i_sram (
        .clk(clk), .rst_n(rst_n),
        .ibuf_wr_addr(ibuf_wr_addr), .ibuf_wr_data(ibuf_wr_data), .ibuf_we(ibuf_we),
        .wbuf_wr_addr(wbuf_wr_addr), .wbuf_wr_data(wbuf_wr_data), .wbuf_we(wbuf_we),
        .ibuf_rd_addr(ibuf_rd_addr), .ibuf_rd_data(ibuf_rd_data),
        .wbuf_rd_addr(wbuf_rd_addr), .wbuf_rd_data(wbuf_rd_data),
        .obuf_wr_addr(obuf_wr_addr), .obuf_wr_data(final_obuf_data), .obuf_we(obuf_write_en),
        .obuf_rd_addr(obuf_rd_addr), .obuf_rd_data(obuf_rd_data)
    );
    
    always @(posedge clk or negedge rst_n) begin
        if (obuf_write_en) begin
            $display("OBUF WRITE: addr=%d data=%x", obuf_wr_addr, final_obuf_data[31:0]);
        end
    end
    
    // 3. Layer Controller
    // Note: The obuf_we and obuf_wr_addr from controller are overridden for pooling.
    // Let's modify the controller instantiation to use an internal address counter for OBUF based on actual valids.
    reg [$clog2(OBUF_DEPTH)-1:0] internal_obuf_wr_addr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) internal_obuf_wr_addr <= 0;
        else if (obuf_write_en) internal_obuf_wr_addr <= internal_obuf_wr_addr + 1;
    end
    assign obuf_wr_addr = internal_obuf_wr_addr;
    
    wire flush_en;
    
    /* verilator lint_off PINCONNECTEMPTY */
    layer_controller #(
        .N(N), .IBUF_DEPTH(IBUF_DEPTH), .WBUF_DEPTH(WBUF_DEPTH)
    ) i_controller (
        .clk(clk), .rst_n(rst_n),
        .cmd_data(cmd_data), .cmd_empty(cmd_empty), .cmd_pop(cmd_pop),
        .ibuf_rd_addr(ibuf_rd_addr), .wbuf_rd_addr(wbuf_rd_addr),
        .npu_start_load(), .npu_start_mac(), .npu_ready(npu_ready),
        .skew_en(skew_en), .skew_w_en(skew_w_en),
        .unskew_valid(unskew_valid),
        .pbuf_addr(pbuf_addr), .accum_en(accum_en), .finish_pass(finish_pass),
        .flush_en(flush_en)
    );
    /* verilator lint_on PINCONNECTEMPTY */
    
    // 4. Skew Buffers (Input Activations)
    // During S_FLUSH, we must feed 0s into the array to push the final partial sums out
    wire [N*DATA_WIDTH-1:0] act_to_skew = flush_en ? {(N*DATA_WIDTH){1'b0}} : ibuf_rd_data;
    
    axis_skew_buffer #(
        .N(N), .DATA_WIDTH(DATA_WIDTH)
    ) i_skew_act (
        .clk(clk), .rst_n(rst_n), .en(skew_en),
        .data_in(act_to_skew), .data_out(skewed_act)
    );
    
    // 5. Systolic Array Core (Bypass npu_core.v FSM to perfectly align with layer_controller pipeline)
    wire array_en = skew_en || skew_w_en || flush_en;
    wire array_load = skew_w_en;
    
    /* verilator lint_off PINCONNECTEMPTY */
    systolic_array #(
        .N(N), .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)
    ) i_array (
        .clk(clk), .rst_n(rst_n),
        .en(array_en),
        .load_weight(array_load),
        .weight_in(wbuf_rd_data),
        .act_in(skewed_act),
        .psum_in({(N*ACC_WIDTH){1'b0}}),
        .act_out(),
        .psum_out(npu_psum_out)
    );
    /* verilator lint_on PINCONNECTEMPTY */
    
    // 6. Unskew Buffer (Outputs)
    axis_unskew_buffer #(
        .N(N), .DATA_WIDTH(ACC_WIDTH)
    ) i_unskew_psum (
        .clk(clk), .rst_n(rst_n), .en(array_en),
        .valid_in(skew_en),
        .data_in(npu_psum_out),
        .data_out(unskewed_psum),
        .valid_out(unskew_valid)
    );
    
    always @(posedge clk or negedge rst_n) begin
        if (unskew_valid) begin
            $display("UNSKEW VALID: psum_out=%x", unskewed_psum[31:0]);
        end
    end
    
    // PBUF Control from Layer Controller
    wire [$clog2(OBUF_DEPTH)-1:0] pbuf_addr;
    wire accum_en, finish_pass;
    
    // 7. Accumulator Buffer (PBUF)
    wire pbuf_valid_out;
    wire [N*ACC_WIDTH-1:0] accumulated_psum;
    
    accumulator_pbuf #(
        .N(N), .ACC_WIDTH(ACC_WIDTH), .PBUF_DEPTH(OBUF_DEPTH)
    ) i_pbuf (
        .clk(clk), .rst_n(rst_n),
        .valid_in(unskew_valid),
        .accum_en(accum_en),
        .finish_pass(finish_pass),
        .pbuf_addr(pbuf_addr),
        .psum_in(unskewed_psum),
        .cpu_we(pbuf_we),
        .cpu_addr(pbuf_wr_addr),
        .cpu_wdata(pbuf_wr_data),
        .valid_out(pbuf_valid_out),
        .psum_out(accumulated_psum)
    );
    
    // 8. Activation / Quantize
    activation_pool #(
        .N(N), .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)
    ) i_act_pool (
        .clk(clk), .rst_n(rst_n),
        .valid_in(pbuf_valid_out),
        .psum_in(accumulated_psum),
        .quant_shift(quant_shift),
        .relu_en(relu_en),
        .valid_out(act_valid_out),
        .act_out(act_data_out)
    );
    
    // 8. Max Pool 2x2
    max_pool_2x2 #(
        .N(N), .DATA_WIDTH(DATA_WIDTH)
    ) i_max_pool (
        .clk(clk), .rst_n(rst_n),
        .pool_en(pool_en),
        .valid_in(act_valid_out),
        .data_in(act_data_out),
        .valid_out(pool_valid_out),
        .data_out(pool_data_out)
    );

endmodule
