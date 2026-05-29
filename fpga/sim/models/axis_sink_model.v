`timescale 1ns/1ps

module axis_sink_model #(
    parameter WIDTH = 32
) (
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] tdata,
    input  wire             tvalid,
    output reg              tready,
    output reg  [31:0]      accepted_count
);
    always @(posedge clk) begin
        if (rst) begin
            tready <= 1'b1;
            accepted_count <= 32'd0;
        end else begin
            tready <= 1'b1;
            if (tvalid && tready) begin
                accepted_count <= accepted_count + 32'd1;
            end
        end
    end
endmodule
