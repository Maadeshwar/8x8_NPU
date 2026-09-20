/* verilator lint_off UNUSEDSIGNAL */
`default_nettype none

module sram_buffers #(
    parameter N = 16,
    parameter DATA_WIDTH = 8,
    parameter IBUF_DEPTH = 1024,
    parameter WBUF_DEPTH = 1024,
    parameter OBUF_DEPTH = 1024
)(
    input  wire clk,
    input  wire rst_n,

    // CPU/DMA Write Interface (Simplified single port for loading)
    input  wire [$clog2(IBUF_DEPTH)-1:0] ibuf_wr_addr,
    input  wire [N*DATA_WIDTH-1:0]       ibuf_wr_data,
    input  wire                          ibuf_we,

    input  wire [$clog2(WBUF_DEPTH)-1:0] wbuf_wr_addr,
    input  wire [N*DATA_WIDTH-1:0]       wbuf_wr_data,
    input  wire                          wbuf_we,
    
    // NPU Read Interface (IBUF & WBUF)
    input  wire [$clog2(IBUF_DEPTH)-1:0] ibuf_rd_addr,
    output reg  [N*DATA_WIDTH-1:0]       ibuf_rd_data,

    input  wire [$clog2(WBUF_DEPTH)-1:0] wbuf_rd_addr,
    output reg  [N*DATA_WIDTH-1:0]       wbuf_rd_data,

    // NPU/Post-Processing Write Interface (OBUF)
    input  wire [$clog2(OBUF_DEPTH)-1:0] obuf_wr_addr,
    input  wire [N*DATA_WIDTH-1:0]       obuf_wr_data, // Assume 8-bit after quantize
    input  wire                          obuf_we,

    // CPU/DMA Read Interface (OBUF)
    input  wire [$clog2(OBUF_DEPTH)-1:0] obuf_rd_addr,
    output reg  [N*DATA_WIDTH-1:0]       obuf_rd_data
);

    // IBUF
    reg [N*DATA_WIDTH-1:0] ibuf_mem [0:IBUF_DEPTH-1];
    always @(posedge clk) begin
        if (ibuf_we) ibuf_mem[ibuf_wr_addr] <= ibuf_wr_data;
        ibuf_rd_data <= ibuf_mem[ibuf_rd_addr];
    end

    // WBUF
    reg [N*DATA_WIDTH-1:0] wbuf_mem [0:WBUF_DEPTH-1];
    always @(posedge clk) begin
        if (wbuf_we) wbuf_mem[wbuf_wr_addr] <= wbuf_wr_data;
        wbuf_rd_data <= wbuf_mem[wbuf_rd_addr];
    end

    // OBUF
    reg [N*DATA_WIDTH-1:0] obuf_mem [0:OBUF_DEPTH-1];
    always @(posedge clk) begin
        if (obuf_we) obuf_mem[obuf_wr_addr] <= obuf_wr_data;
        obuf_rd_data <= obuf_mem[obuf_rd_addr];
    end

endmodule
