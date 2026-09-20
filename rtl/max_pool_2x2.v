`default_nettype none

module max_pool_2x2 #(
    parameter N = 16,        // Must be even. e.g., 16 input elements
    parameter DATA_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,

    input  wire                      pool_en,
    
    input  wire                      valid_in,
    input  wire [N*DATA_WIDTH-1:0]   data_in,
    
    output reg                       valid_out,
    output reg  [(N/2)*DATA_WIDTH-1:0] data_out
);

    // State to track if we are on the first row (store) or second row (compare & output)
    reg row_phase;
    
    // Register to store the first row's 1x2 max results
    reg [(N/2)*DATA_WIDTH-1:0] row_buffer;

    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_phase <= 0;
            valid_out <= 0;
            data_out  <= 0;
            row_buffer <= 0;
        end else begin
            valid_out <= 0;
            
            if (valid_in) begin
                if (!pool_en) begin
                    // Bypass pooling (Note: output width mismatch if bypassed. 
                    // In a real system, bypass means packing or padding. 
                    // For simplicity, we just output the lower half if bypassed, 
                    // or require N to match. Let's just output lower half for bypass).
                    valid_out <= 1;
                    data_out  <= data_in[(N/2)*DATA_WIDTH-1:0];
                end else begin
                    if (row_phase == 0) begin
                        // Phase 0: Compute 1x2 horizontal max and store
                        for (i = 0; i < N/2; i = i + 1) begin
                            reg signed [DATA_WIDTH-1:0] val0;
                            reg signed [DATA_WIDTH-1:0] val1;
                            val0 = $signed(data_in[(2*i)*DATA_WIDTH +: DATA_WIDTH]);
                            val1 = $signed(data_in[(2*i+1)*DATA_WIDTH +: DATA_WIDTH]);
                            
                            row_buffer[i*DATA_WIDTH +: DATA_WIDTH] <= (val0 > val1) ? val0 : val1;
                        end
                        row_phase <= 1;
                    end else begin
                        // Phase 1: Compute 1x2 horizontal max, then 2x2 vertical max with row_buffer
                        for (i = 0; i < N/2; i = i + 1) begin
                            reg signed [DATA_WIDTH-1:0] val0;
                            reg signed [DATA_WIDTH-1:0] val1;
                            reg signed [DATA_WIDTH-1:0] h_max;
                            reg signed [DATA_WIDTH-1:0] v_max;
                            
                            val0 = $signed(data_in[(2*i)*DATA_WIDTH +: DATA_WIDTH]);
                            val1 = $signed(data_in[(2*i+1)*DATA_WIDTH +: DATA_WIDTH]);
                            h_max = (val0 > val1) ? val0 : val1;
                            
                            v_max = $signed(row_buffer[i*DATA_WIDTH +: DATA_WIDTH]);
                            
                            data_out[i*DATA_WIDTH +: DATA_WIDTH] <= (h_max > v_max) ? h_max : v_max;
                        end
                        valid_out <= 1;
                        row_phase <= 0;
                    end
                end
            end
        end
    end

endmodule
