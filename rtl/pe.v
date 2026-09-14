`default_nettype none

module pe #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  en,
    input  wire                  load_weight,
    input  wire [DATA_WIDTH-1:0] weight_in,
    input  wire [DATA_WIDTH-1:0] act_in,
    input  wire [ACC_WIDTH-1:0]  psum_in,
    output wire [DATA_WIDTH-1:0] weight_out,
    output reg  [DATA_WIDTH-1:0] act_out,
    output reg  [ACC_WIDTH-1:0]  psum_out
);

    reg signed [DATA_WIDTH-1:0] weight_reg;
    assign weight_out = weight_reg;
    
    wire signed [DATA_WIDTH-1:0] s_act = $signed(act_in);
    wire signed [DATA_WIDTH-1:0] s_weight = $signed(weight_reg);
    wire signed [ACC_WIDTH-1:0] s_psum = $signed(psum_in);

    // MAC operation
    wire signed [ACC_WIDTH-1:0] mult_res = s_act * s_weight;
    wire signed [ACC_WIDTH-1:0] add_res = mult_res + s_psum;

    always @(posedge clk) begin
        if (!rst_n) begin
            weight_reg <= {DATA_WIDTH{1'b0}};
            act_out    <= {DATA_WIDTH{1'b0}};
            psum_out   <= {ACC_WIDTH{1'b0}};
        end else if (en) begin
            if (load_weight) begin
                weight_reg <= weight_in;
                act_out    <= {DATA_WIDTH{1'b0}};
                psum_out   <= {ACC_WIDTH{1'b0}};
            end else begin
                act_out    <= act_in;
                psum_out   <= add_res;
            end
        end
    end

endmodule

