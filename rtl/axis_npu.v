`default_nettype none

// AXI4-Stream Top-Level Wrapper for the Systolic NPU
// Users only need to instantiate this module and set N/DATA_WIDTH/ACC_WIDTH.
// The internal files (pe.v, systolic_array.v, skew_buffers.v) never need to change.
module axis_npu #(
    parameter N = 8,           // Array dimension (NxN grid of PEs)
    parameter DATA_WIDTH = 8,  // Bit-width of input activations and weights
    parameter ACC_WIDTH = 32   // Bit-width of accumulated partial sums
)(
    input  wire                               clk,
    input  wire                               rst_n,

    // AXI4-Stream for Weights (Input)
    input  wire [N*DATA_WIDTH-1:0]            s_axis_w_tdata,
    input  wire                               s_axis_w_tvalid,
    output wire                               s_axis_w_tready,
    input  wire                               s_axis_w_tlast,

    // AXI4-Stream for Activations (Input)
    input  wire [N*DATA_WIDTH-1:0]            s_axis_a_tdata,
    input  wire                               s_axis_a_tvalid,
    output wire                               s_axis_a_tready,
    input  wire                               s_axis_a_tlast,

    // AXI4-Stream for Partial Sums (Output)
    output wire [N*ACC_WIDTH-1:0]             m_axis_out_tdata,
    output wire                               m_axis_out_tvalid,
    input  wire                               m_axis_out_tready,
    output wire                               m_axis_out_tlast
);

    // States
    localparam STATE_IDLE  = 2'd0;
    localparam STATE_LOADW = 2'd1;
    localparam STATE_MAC   = 2'd2;
    localparam STATE_FLUSH = 2'd3;

    reg [1:0] state, next_state;
    reg [6:0] flush_counter, next_flush_counter;

    // Handshakes
    wire w_fire = s_axis_w_tvalid && s_axis_w_tready;
    wire a_fire = s_axis_a_tvalid && s_axis_a_tready;
    wire out_fire = m_axis_out_tvalid && m_axis_out_tready;

    // Array signals
    reg array_en;
    reg array_load;

    // Internal data routing
    wire [N*DATA_WIDTH-1:0] skewed_act;
    wire [N*ACC_WIDTH-1:0]  array_psum_out;
    wire [N*ACC_WIDTH-1:0]  unskewed_psum;
    wire                    unskew_valid;

    // Skew logic
    axis_skew_buffer #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH)
    ) act_skew (
        .clk(clk),
        .rst_n(rst_n),
        .en(array_en),
        .data_in(state == STATE_MAC ? s_axis_a_tdata : {N*DATA_WIDTH{1'b0}}),
        .data_out(skewed_act)
    );

    // Systolic array
    systolic_array #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) array_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(array_en),
        .load_weight(array_load),
        .weight_in(s_axis_w_tdata),
        .act_in(skewed_act),
        .psum_in({N*ACC_WIDTH{1'b0}}), // Baseline
        .act_out(),
        .psum_out(array_psum_out)
    );

    // Unskew logic
    axis_unskew_buffer #(
        .N(N),
        .DATA_WIDTH(ACC_WIDTH)
    ) psum_unskew (
        .clk(clk),
        .rst_n(rst_n),
        .en(array_en && !array_load), // Unskew only steps when array is computing MACs
        .valid_in(a_fire),            // Only shift valid exactly when an activation row is accepted
        .data_in(array_psum_out),
        .data_out(unskewed_psum),
        .valid_out(unskew_valid)
    );

    // Output buffering (simplified valid pass-through for the valid unskew data)
    assign m_axis_out_tdata = unskewed_psum;
    assign m_axis_out_tvalid = unskew_valid;
    
    // We assume the receiver is always ready in this simple flush model, 
    // or we'd need a FIFO at the output. 
    // AXI protocol dictates valid cannot depend on ready, which is fine here.
    
    // TLAST logic for output
    // The pipeline latency from input tlast to output tlast is exactly 2N-2 cycles.
    reg [2*N-2:0] tlast_shift;
    always @(posedge clk) begin
        if (!rst_n) tlast_shift <= 0;
        else if (array_en && !array_load) tlast_shift <= {tlast_shift[2*N-3:0], (a_fire && s_axis_a_tlast)};
        else tlast_shift <= {tlast_shift[2*N-3:0], 1'b0};
    end
    assign m_axis_out_tlast = tlast_shift[2*N-2];

    // FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            flush_counter <= 0;
        end else begin
            state <= next_state;
            flush_counter <= next_flush_counter;
        end
    end

    assign s_axis_w_tready = (state == STATE_LOADW) || (state == STATE_IDLE);
    assign s_axis_a_tready = (state == STATE_MAC) && (!unskew_valid || m_axis_out_tready); 
    // Backpressure if output isn't ready and valid is high. 
    // Wait, backpressuring the array requires freezing `array_en`.

    always @(*) begin
        next_state = state;
        next_flush_counter = flush_counter;
        array_en = 0;
        array_load = 0;

        // If valid output is waiting and downstream is not ready, freeze the pipeline
        if (unskew_valid && !m_axis_out_tready) begin
            array_en = 0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (s_axis_w_tvalid) begin
                        next_state = STATE_LOADW;
                        array_en = 1;
                        array_load = 1;
                    end else if (s_axis_a_tvalid) begin
                        next_state = STATE_MAC;
                        array_en = 1;
                    end
                end
                
                STATE_LOADW: begin
                    if (s_axis_w_tvalid) begin
                        array_en = 1;
                        array_load = 1;
                        if (s_axis_w_tlast) begin
                            next_state = STATE_IDLE;
                        end
                    end
                end
                
                STATE_MAC: begin
                    if (s_axis_a_tvalid) begin
                        array_en = 1;
                        if (s_axis_a_tlast) begin
                            next_state = STATE_FLUSH;
                            next_flush_counter = 0;
                        end
                    end
                end
                
                STATE_FLUSH: begin
                    array_en = 1; // Keep clocking the pipeline to flush it out
                    next_flush_counter = flush_counter + 1;
                    // Flush takes 2N - 1 cycles to complete unskew
                    if (flush_counter >= (2 * N - 1)) begin
                        next_state = STATE_IDLE;
                    end
                end
            endcase
        end
    end

    // Assertions
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (rst_n) begin
            if (s_axis_w_tvalid && !s_axis_w_tready && !$past(s_axis_w_tvalid))
                $display("[%0t] Warning: Weights arriving but NPU not ready", $time);
        end
    end
    `endif

endmodule
