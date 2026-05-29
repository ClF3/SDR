`timescale 1ns/1ps

module reset_sync #(
    parameter STAGES = 3
) (
    input  wire clk,
    input  wire arst_n,
    output wire rst
);
    reg [STAGES-1:0] sync_shreg;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            sync_shreg <= {STAGES{1'b1}};
        end else begin
            sync_shreg <= {sync_shreg[STAGES-2:0], 1'b0};
        end
    end

    assign rst = sync_shreg[STAGES-1];
endmodule
