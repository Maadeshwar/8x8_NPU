`default_nettype none

module systolic_array #(
    parameter N = 8,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
)(
    input  wire                               clk,
    input  wire                               rst_n,
    input  wire                               en,
    input  wire                               load_weight,
    input  wire [N*DATA_WIDTH-1:0]           weight_in, // N parallel weight streams (one per column)
    input  wire [N*DATA_WIDTH-1:0]            act_in,    // N parallel act streams (one per row)
    input  wire [N*ACC_WIDTH-1:0]             psum_in,   // N parallel psum streams (one per column)
    output wire [N*DATA_WIDTH-1:0]            act_out,
    output wire [N*ACC_WIDTH-1:0]             psum_out
);

    // 2D wire arrays for interconnects
    wire [DATA_WIDTH-1:0] weight_wire [N:0][N-1:0];
    wire [DATA_WIDTH-1:0] act_wire    [N-1:0][N:0];
    wire [ACC_WIDTH-1:0]  psum_wire   [N:0][N-1:0];

    genvar i, j;
    generate
        // Assign inputs to the boundaries
        for (j = 0; j < N; j = j + 1) begin : init_cols
            assign weight_wire[0][j] = weight_in[j*DATA_WIDTH +: DATA_WIDTH];
            assign psum_wire[0][j]   = psum_in[j*ACC_WIDTH +: ACC_WIDTH];
            assign psum_out[j*ACC_WIDTH +: ACC_WIDTH] = psum_wire[N][j];
        end

        for (i = 0; i < N; i = i + 1) begin : init_rows
            assign act_wire[i][0] = act_in[i*DATA_WIDTH +: DATA_WIDTH];
            assign act_out[i*DATA_WIDTH +: DATA_WIDTH] = act_wire[i][N];
        end

        // Instantiate the N x N grid of PEs
        for (i = 0; i < N; i = i + 1) begin : row
            for (j = 0; j < N; j = j + 1) begin : col
                pe #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH)
                ) pe_inst (
                    .clk(clk),
                    .rst_n(rst_n),
                    .en(en),
                    .load_weight(load_weight),
                    .weight_in(weight_wire[i][j]),
                    .act_in(act_wire[i][j]),
                    .psum_in(psum_wire[i][j]),
                    .weight_out(weight_wire[i+1][j]),
                    .act_out(act_wire[i][j+1]),
                    .psum_out(psum_wire[i+1][j])
                );
            end
        end
    endgenerate

endmodule

