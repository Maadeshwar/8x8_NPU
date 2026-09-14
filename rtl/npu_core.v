`default_nettype none

module npu_core #(
    parameter N = 8,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
)(
    input  wire                               clk,
    input  wire                               rst_n,
    
    // Control interface
    input  wire                               start_load, // Pulse to start loading weights
    input  wire                               start_mac,  // Level signal to enable MAC streaming
    output reg                                ready,      // High when IDLE
    
    // Data interface
    input  wire [N*DATA_WIDTH-1:0]            weight_in,  // N weights per cycle
    input  wire [N*DATA_WIDTH-1:0]            act_in,     // N acts per cycle
    input  wire [N*ACC_WIDTH-1:0]             psum_in,    // Initial partial sums (usually 0)
    
    output wire [N*DATA_WIDTH-1:0]            act_out,
    output wire [N*ACC_WIDTH-1:0]             psum_out
);

    // FSM States
    localparam STATE_IDLE = 2'b00;
    localparam STATE_LOAD = 2'b01;
    localparam STATE_MAC  = 2'b10;

    reg [1:0] state, next_state;
    // We need a wider counter to handle N up to 64
    reg [6:0] counter, next_counter;
    
    // Control signals for array
    reg array_en;
    reg array_load;

    // FSM sequential logic
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            counter <= 7'd0;
        end else begin
            state <= next_state;
            counter <= next_counter;
        end
    end

    // FSM combinational logic
    always @(*) begin
        next_state = state;
        next_counter = counter;
        ready = 1'b0;
        array_en = 1'b0;
        array_load = 1'b0;
        
        case (state)
            STATE_IDLE: begin
                ready = 1'b1;
                next_counter = 7'd0;
                if (start_load) begin
                    next_state = STATE_LOAD;
                end else if (start_mac) begin
                    next_state = STATE_MAC;
                    array_en = 1'b1; // Sample immediately on transition
                end
            end
            
            STATE_LOAD: begin
                array_en = 1'b1;
                array_load = 1'b1;
                if (counter == (N - 1)) begin
                    next_state = STATE_IDLE;
                end else begin
                    next_counter = counter + 7'd1;
                end
            end
            
            STATE_MAC: begin
                array_en = 1'b1;
                array_load = 1'b0;
                if (!start_mac) begin
                    next_state = STATE_IDLE;
                end
            end
            
            default: next_state = STATE_IDLE;
        endcase
    end

    systolic_array #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) array_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(array_en),
        .load_weight(array_load),
        .weight_in(weight_in),
        .act_in(act_in),
        .psum_in(psum_in),
        .act_out(act_out),
        .psum_out(psum_out)
    );

endmodule
