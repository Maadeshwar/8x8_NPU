`default_nettype none

module activation_pool #(
    parameter N = 16,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst_n,
    
    input  wire                   valid_in,
    input  wire [N*ACC_WIDTH-1:0] psum_in,
    input  wire [4:0]             quant_shift, // Shift amount for quantization
    input  wire                   relu_en,
    
    output reg                    valid_out,
    output reg  [N*DATA_WIDTH-1:0] act_out
);

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 0;
            act_out   <= 0;
        end else begin
            valid_out <= valid_in;
            for (i = 0; i < N; i = i + 1) begin
                // Extract 32-bit scalar
                reg signed [ACC_WIDTH-1:0] val;
                reg signed [ACC_WIDTH-1:0] relu_val;
                reg signed [ACC_WIDTH-1:0] quant_val;
                
                val = $signed(psum_in[i*ACC_WIDTH +: ACC_WIDTH]);
                
                // ReLU
                if (relu_en && val < 0) begin
                    relu_val = 0;
                end else begin
                    relu_val = val;
                end
                
                // Quantize (Shift Right)
                quant_val = relu_val >>> quant_shift;
                
                // Clamp to 8-bit signed range (-128 to 127)
                if (quant_val > 127) begin
                    act_out[i*DATA_WIDTH +: DATA_WIDTH] <= 8'd127;
                end else if (quant_val < -128) begin
                    act_out[i*DATA_WIDTH +: DATA_WIDTH] <= -8'd128;
                end else begin
                    act_out[i*DATA_WIDTH +: DATA_WIDTH] <= quant_val[7:0];
                end
            end
        end
    end

endmodule
