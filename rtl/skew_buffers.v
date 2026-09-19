`default_nettype none

module axis_skew_buffer #(
    parameter N = 8,
    parameter DATA_WIDTH = 8
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,
    input  wire [N*DATA_WIDTH-1:0]  data_in,
    output wire [N*DATA_WIDTH-1:0]  data_out
);

    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : gen_skew
            if (i == 0) begin
                assign data_out[0 +: DATA_WIDTH] = data_in[0 +: DATA_WIDTH];
            end else begin
                reg [DATA_WIDTH-1:0] shift_reg [0:i-1];
                integer j_idx;
                always @(posedge clk) begin
                    if (!rst_n) begin
                        for (j_idx = 0; j_idx < i; j_idx = j_idx + 1) shift_reg[j_idx] <= 0;
                    end else if (en) begin
                        shift_reg[0] <= data_in[i*DATA_WIDTH +: DATA_WIDTH];
                        for (j_idx = 1; j_idx < i; j_idx = j_idx + 1) begin
                            shift_reg[j_idx] <= shift_reg[j_idx-1];
                        end
                    end
                end
                assign data_out[i*DATA_WIDTH +: DATA_WIDTH] = shift_reg[i-1];
            end
        end
    endgenerate
endmodule

module axis_unskew_buffer #(
    parameter N = 8,
    parameter DATA_WIDTH = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,
    input  wire                     valid_in,
    input  wire [N*DATA_WIDTH-1:0]  data_in,
    output wire [N*DATA_WIDTH-1:0]  data_out,
    output wire                     valid_out
);

    // Track valid pipeline
    reg [2*N-2:0] valid_shift;
    always @(posedge clk) begin
        if (!rst_n) valid_shift <= 0;
        else if (en) valid_shift <= {valid_shift[2*N-3:0], valid_in};
    end
    assign valid_out = valid_shift[2*N-2];

    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : gen_unskew
            localparam DELAY = N - 1 - i;
            if (DELAY == 0) begin
                assign data_out[i*DATA_WIDTH +: DATA_WIDTH] = data_in[i*DATA_WIDTH +: DATA_WIDTH];
            end else begin
                reg [DATA_WIDTH-1:0] shift_reg [0:DELAY-1];
                integer j_idx;
                always @(posedge clk) begin
                    if (!rst_n) begin
                        for (j_idx = 0; j_idx < DELAY; j_idx = j_idx + 1) shift_reg[j_idx] <= 0;
                    end else if (en) begin
                        shift_reg[0] <= data_in[i*DATA_WIDTH +: DATA_WIDTH];
                        for (j_idx = 1; j_idx < DELAY; j_idx = j_idx + 1) begin
                            shift_reg[j_idx] <= shift_reg[j_idx-1];
                        end
                    end
                end
                assign data_out[i*DATA_WIDTH +: DATA_WIDTH] = shift_reg[DELAY-1];
            end
        end
    endgenerate
endmodule
