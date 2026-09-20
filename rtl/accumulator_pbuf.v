/* verilator lint_off BLKSEQ */
`default_nettype none

module accumulator_pbuf #(
    parameter N = 8,
    parameter ACC_WIDTH = 32,
    parameter PBUF_DEPTH = 1024
)(
    input  wire clk,
    input  wire rst_n,

    // Control
    input  wire        valid_in,
    input  wire        accum_en,    // 0 = Overwrite PBUF (First pass w/o bias), 1 = Add to PBUF (Passes w/ bias or accum)
    input  wire        finish_pass, // 1 = Output to Activation/Pool (Final pass)
    
    // NPU Address (shared for read/write since we do a read-modify-write pipeline)
    input  wire [$clog2(PBUF_DEPTH)-1:0] pbuf_addr,

    // Data from NPU (Unskewed)
    input  wire [N*ACC_WIDTH-1:0] psum_in,
    
    // CPU/DMA Write Interface (For Preloading Biases)
    input  wire                           cpu_we,
    input  wire [$clog2(PBUF_DEPTH)-1:0]  cpu_addr,
    input  wire [N*ACC_WIDTH-1:0]         cpu_wdata,
    
    // Data to Activation (Final pass)
    output reg                    valid_out,
    output reg  [N*ACC_WIDTH-1:0] psum_out
);

    // 32-bit Partial Sum / Bias SRAM
    reg [N*ACC_WIDTH-1:0] pbuf_mem [0:PBUF_DEPTH-1];
    
    // CPU/DMA Write Port is handled in the main always block
    
    // Pipeline registers to align read data with incoming psum_in
    // Since pbuf_addr is provided along with valid_in, it takes 1 cycle to read SRAM.
    // We must delay valid_in, accum_en, finish_pass, and psum_in by 1 cycle.
    
    reg        valid_in_d;
    reg        accum_en_d;
    reg        finish_pass_d;
    reg [$clog2(PBUF_DEPTH)-1:0] pbuf_addr_d;
    reg [N*ACC_WIDTH-1:0] psum_in_d;
    
    reg [N*ACC_WIDTH-1:0] pbuf_rdata;
    reg [N*ACC_WIDTH-1:0] next_psum;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_in_d <= 0;
            accum_en_d <= 0;
            finish_pass_d <= 0;
            pbuf_addr_d <= 0;
            psum_in_d <= 0;
            valid_out <= 0;
            psum_out <= 0;
        end else begin
            // Stage 1: Read SRAM
            pbuf_rdata <= pbuf_mem[pbuf_addr]; // Synchronous read
            
            // Delay control signals
            valid_in_d <= valid_in;
            accum_en_d <= accum_en;
            finish_pass_d <= finish_pass;
            pbuf_addr_d <= pbuf_addr;
            psum_in_d <= psum_in;
            
            valid_out <= 0;
            
            // Stage 2: Accumulate and Writeback / Output
            if (valid_in_d) begin
                for (i = 0; i < N; i = i + 1) begin
                    reg signed [ACC_WIDTH-1:0] p_in;
                    reg signed [ACC_WIDTH-1:0] p_mem;
                    reg signed [ACC_WIDTH-1:0] p_sum;
                    
                    p_in  = $signed(psum_in_d[i*ACC_WIDTH +: ACC_WIDTH]);
                    p_mem = $signed(pbuf_rdata[i*ACC_WIDTH +: ACC_WIDTH]);
                    
                    if (accum_en_d) begin
                        p_sum = p_in + p_mem;
                    end else begin
                        p_sum = p_in; // First pass, overwrite
                    end
                    
                    next_psum[i*ACC_WIDTH +: ACC_WIDTH] = p_sum;
                end
                
                // If it is the final pass, send it down the pipeline
                if (finish_pass_d) begin
                    valid_out <= 1;
                    psum_out <= next_psum;
                end
            end
            
            // Memory writes
            if (cpu_we) begin
                pbuf_mem[cpu_addr] <= cpu_wdata;
            end else if (valid_in_d && !finish_pass_d) begin
                pbuf_mem[pbuf_addr_d] <= next_psum;
            end
        end
    end

endmodule
