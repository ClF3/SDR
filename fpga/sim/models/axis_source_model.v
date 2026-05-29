`timescale 1ns/1ps

module axis_source_model #(
    parameter WIDTH = 32
) (
    input  wire             clk,
    input  wire             rst,
    output reg  [WIDTH-1:0] tdata,
    output reg              tvalid,
    input  wire             tready
);
    always @(posedge clk) begin
        if (rst) begin
            tdata  <= {WIDTH{1'b0}};
            tvalid <= 1'b0;
        end else begin
            tvalid <= 1'b1;
            if (!tvalid || tready) begin
                tdata <= tdata + {{(WIDTH-1){1'b0}}, 1'b1};
            end
        end
    end
endmodule
