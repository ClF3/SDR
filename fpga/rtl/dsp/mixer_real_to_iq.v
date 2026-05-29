`timescale 1ns/1ps

module mixer_real_to_iq #(
    parameter SAMPLE_WIDTH = 16,
    parameter TRIG_WIDTH = 16,
    parameter OUT_WIDTH = 32
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire signed [SAMPLE_WIDTH-1:0] sample_in,
    input  wire signed [TRIG_WIDTH-1:0] cos_in,
    input  wire signed [TRIG_WIDTH-1:0] sin_in,
    input  wire                         valid_in,
    output reg  signed [OUT_WIDTH-1:0]  i_out,
    output reg  signed [OUT_WIDTH-1:0]  q_out,
    output reg                          valid_out
);
    wire signed [SAMPLE_WIDTH+TRIG_WIDTH-1:0] prod_i;
    wire signed [SAMPLE_WIDTH+TRIG_WIDTH-1:0] prod_q;
    wire signed [OUT_WIDTH-1:0] i_scaled;
    wire signed [OUT_WIDTH-1:0] q_scaled;

    assign prod_i = sample_in * cos_in;
    assign prod_q = sample_in * sin_in;
    assign i_scaled = {{(OUT_WIDTH-(SAMPLE_WIDTH+TRIG_WIDTH)){prod_i[SAMPLE_WIDTH+TRIG_WIDTH-1]}}, prod_i} >>> (TRIG_WIDTH-1);
    assign q_scaled = -({{(OUT_WIDTH-(SAMPLE_WIDTH+TRIG_WIDTH)){prod_q[SAMPLE_WIDTH+TRIG_WIDTH-1]}}, prod_q} >>> (TRIG_WIDTH-1));

    always @(posedge clk) begin
        if (rst) begin
            i_out     <= {OUT_WIDTH{1'b0}};
            q_out     <= {OUT_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                i_out <= i_scaled;
                q_out <= q_scaled;
            end
        end
    end
endmodule
