`timescale 1ns/1ps

module timestamp_counter (
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_valid,
    output reg  [63:0] timestamp
);
    always @(posedge clk) begin
        if (rst) begin
            timestamp <= 64'd0;
        end else if (sample_valid) begin
            timestamp <= timestamp + 64'd1;
        end
    end
endmodule
