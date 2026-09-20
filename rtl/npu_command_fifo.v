`default_nettype none

module npu_command_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH_LOG2 = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,
    
    // CPU Write Interface
    input  wire                   push,
    input  wire [DATA_WIDTH-1:0]  data_in,
    output wire                   full,
    
    // NPU Read Interface
    input  wire                   pop,
    output wire [DATA_WIDTH-1:0]  data_out,
    output wire                   empty
);

    localparam DEPTH = 1 << DEPTH_LOG2;
    
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [DEPTH_LOG2:0] write_ptr;
    reg [DEPTH_LOG2:0] read_ptr;
    
    assign empty = (write_ptr == read_ptr);
    assign full  = (write_ptr[DEPTH_LOG2] != read_ptr[DEPTH_LOG2]) &&
                   (write_ptr[DEPTH_LOG2-1:0] == read_ptr[DEPTH_LOG2-1:0]);
                   
    assign data_out = mem[read_ptr[DEPTH_LOG2-1:0]];
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= 0;
            read_ptr  <= 0;
        end else begin
            if (push && !full) begin
                mem[write_ptr[DEPTH_LOG2-1:0]] <= data_in;
                write_ptr <= write_ptr + 1;
            end
            if (pop && !empty) begin
                read_ptr <= read_ptr + 1;
            end
        end
    end

endmodule
