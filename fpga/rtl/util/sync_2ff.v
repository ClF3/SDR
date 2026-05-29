`timescale 1ns/1ps

module sync_2ff #(
    parameter WIDTH = 1
) (
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] async_in,
    output wire [WIDTH-1:0] sync_out
);
    reg [WIDTH-1:0] sync0;
    reg [WIDTH-1:0] sync1;

    always @(posedge clk) begin
        if (rst) begin
            sync0 <= {WIDTH{1'b0}};
            sync1 <= {WIDTH{1'b0}};
        end else begin
            sync0 <= async_in;
            sync1 <= sync0;
        end
    end

    assign sync_out = sync1;
endmodule
