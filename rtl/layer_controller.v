/* verilator lint_off CASEINCOMPLETE */
/* verilator lint_off UNUSEDPARAM */
`default_nettype none

module layer_controller #(
    parameter N = 8,
    parameter IBUF_DEPTH = 1024,
    parameter WBUF_DEPTH = 1024,
    parameter OBUF_DEPTH = 1024
)(
    input  wire clk,
    input  wire rst_n,

    // Command FIFO interface
    input  wire [31:0] cmd_data,
    input  wire        cmd_empty,
    output reg         cmd_pop,
    
    // SRAM Address interface
    output reg [$clog2(IBUF_DEPTH)-1:0] ibuf_rd_addr,
    output reg [$clog2(WBUF_DEPTH)-1:0] wbuf_rd_addr,
    
    // NPU Core interface
    output reg         npu_start_load,
    output reg         npu_start_mac,
    input  wire        npu_ready,
    
    // Skew buffer enable
    output reg         skew_en,
    output reg         skew_w_en,
    
    // PBUF Control
    input  wire        unskew_valid,
    output reg [$clog2(1024)-1:0] pbuf_addr,
    output reg         accum_en,
    output reg         finish_pass,
    
    // Flush
    output reg         flush_en
);

    localparam OP_LOAD_WEIGHTS = 4'd1;
    localparam OP_RUN_MAC      = 4'd2;
    localparam OP_SET_TILER    = 4'd3;

    localparam S_IDLE = 3'd0;
    localparam S_LOAD = 3'd1;
    localparam S_LOAD_WAIT = 3'd2;
    localparam S_RUN  = 3'd3;
    localparam S_FLUSH = 3'd4;
    localparam S_RUN_WAIT = 3'd5;
    localparam S_TILE_NEXT = 3'd6;

    reg [2:0] state, next_state;
    reg [25:0] counter;
    reg [25:0] mac_cycles;
    
    // Tiler registers
    reg [15:0] tile_counter;
    reg [15:0] tile_limit;

    // Stage 1: Sequential State Update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else state <= next_state;
    end

    // Stage 2: Combinational Next-State Logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (!cmd_empty && npu_ready) begin
                    if (cmd_data[31:28] == OP_LOAD_WEIGHTS) next_state = S_LOAD;
                    else if (cmd_data[31:28] == OP_RUN_MAC) next_state = S_RUN;
                end
            end
            S_LOAD: begin
                if (counter == 0) next_state = S_LOAD_WAIT;
            end
            S_LOAD_WAIT: begin
                if (npu_ready) next_state = S_IDLE;
            end
            S_RUN: begin
                if (counter >= mac_cycles) next_state = S_FLUSH;
            end
            S_FLUSH: begin
                if (counter >= mac_cycles + (2*N)) next_state = S_RUN_WAIT;
            end
            S_RUN_WAIT: begin
                if (npu_ready && !unskew_valid) begin
                    if (tile_counter < tile_limit) next_state = S_TILE_NEXT;
                    else next_state = S_IDLE;
                end
            end
            S_TILE_NEXT: begin
                next_state = S_RUN;
            end
            default: next_state = S_IDLE;
        endcase
    end

    reg [1:0] mac_delay_sr;
    
    // Stage 3: Sequential Output Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_pop <= 0;
            ibuf_rd_addr <= 0;
            wbuf_rd_addr <= 0;
            pbuf_addr <= 0;
            accum_en <= 0;
            finish_pass <= 0;
            npu_start_load <= 0;
            npu_start_mac <= 0;
            mac_delay_sr <= 0;
            skew_en <= 0;
            skew_w_en <= 0;
            counter <= 0;
            mac_cycles <= 0;
            tile_counter <= 0;
            tile_limit <= 0;
            flush_en <= 0;
        end else begin
            cmd_pop <= 0;
            npu_start_load <= 0;
            
            // Advance pbuf_addr when unskew is valid
            if (unskew_valid) pbuf_addr <= pbuf_addr + 1;
            
            // Delay npu_start_mac by 2 cycles to align with SRAM (1 cycle) + Skew Buffer (1 cycle)
            npu_start_mac <= mac_delay_sr[1];

            case (state)
                S_IDLE: begin
                    skew_en <= 0;
                    skew_w_en <= 0;
                    mac_delay_sr <= 2'b00;
                    flush_en <= 0;
                    pbuf_addr <= 0;
                    
                    if (!cmd_empty && npu_ready) begin
                        cmd_pop <= 1;
                        if (cmd_data[31:28] == OP_SET_TILER) begin
                            tile_limit <= cmd_data[15:0];
                        end else if (cmd_data[31:28] == OP_LOAD_WEIGHTS) begin
                            npu_start_load <= 1;
                            counter <= cmd_data[25:0];
                        end else if (cmd_data[31:28] == OP_RUN_MAC) begin
                            mac_delay_sr[0] <= 1'b1;
                            accum_en <= cmd_data[27];
                            finish_pass <= cmd_data[26];
                            mac_cycles <= cmd_data[25:0];
                            counter <= 0;
                            tile_counter <= 0;
                        end
                    end
                end
                
                S_LOAD: begin
                    if (counter > 0) begin
                        wbuf_rd_addr <= wbuf_rd_addr + 1;
                        skew_w_en <= 1; 
                        counter <= counter - 1;
                    end else begin
                        skew_w_en <= 0;
                    end
                end
                
                S_LOAD_WAIT: begin
                    skew_w_en <= 0;
                end
                
                S_RUN: begin
                    flush_en <= 0;
                    mac_delay_sr <= {mac_delay_sr[0], 1'b1};
                    if (counter < mac_cycles) begin
                        ibuf_rd_addr <= ibuf_rd_addr + 1;
                        skew_en <= 1;
                        counter <= counter + 1;
                    end
                end
                
                S_FLUSH: begin
                    // Keep start_mac and skew_en high to flush pipeline
                    mac_delay_sr <= {mac_delay_sr[0], 1'b1};
                    flush_en <= 1;
                    skew_en <= 1;
                    counter <= counter + 1;
                end
                
                S_RUN_WAIT: begin
                    skew_en <= 0;
                    mac_delay_sr <= {mac_delay_sr[0], 1'b0};
                    flush_en <= 0;
                end
                
                S_TILE_NEXT: begin
                    tile_counter <= tile_counter + 1;
                    counter <= 0;
                    pbuf_addr <= 0;
                    mac_delay_sr <= 2'b01;
                    flush_en <= 0;
                end
            endcase
        end
    end

endmodule
