`timescale 1ns/1ps

module iq_gain_sat #(
    parameter DATA_WIDTH = 56,
    parameter OUT_WIDTH = 16
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire signed [DATA_WIDTH-1:0] i_in,
    input  wire signed [DATA_WIDTH-1:0] q_in,
    input  wire                         valid_in,
    input  wire [5:0]                   gain_shift,
    output reg  signed [OUT_WIDTH-1:0]  i_out,
    output reg  signed [OUT_WIDTH-1:0]  q_out,
    output reg                          valid_out,
    output reg                          clipped
);
    localparam signed [DATA_WIDTH-1:0] MAX_OUT_EXT =
        {{(DATA_WIDTH-OUT_WIDTH){1'b0}}, {1'b0, {(OUT_WIDTH-1){1'b1}}}};
    localparam signed [DATA_WIDTH-1:0] MIN_OUT_EXT =
        {{(DATA_WIDTH-OUT_WIDTH){1'b1}}, {1'b1, {(OUT_WIDTH-1){1'b0}}}};

    function signed [OUT_WIDTH-1:0] shift_sat;
        input signed [DATA_WIDTH-1:0] value;
        input [5:0] shift;
        reg signed [DATA_WIDTH-1:0] shifted;
        begin
            shifted = value >>> shift;
            if (shifted > MAX_OUT_EXT) begin
                shift_sat = {1'b0, {(OUT_WIDTH-1){1'b1}}};
            end else if (shifted < MIN_OUT_EXT) begin
                shift_sat = {1'b1, {(OUT_WIDTH-1){1'b0}}};
            end else begin
                shift_sat = shifted[OUT_WIDTH-1:0];
            end
        end
    endfunction

    function is_clipped;
        input signed [DATA_WIDTH-1:0] value;
        input [5:0] shift;
        reg signed [DATA_WIDTH-1:0] shifted;
        begin
            shifted = value >>> shift;
            is_clipped = (shifted > MAX_OUT_EXT) || (shifted < MIN_OUT_EXT);
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            i_out     <= {OUT_WIDTH{1'b0}};
            q_out     <= {OUT_WIDTH{1'b0}};
            valid_out <= 1'b0;
            clipped   <= 1'b0;
        end else begin
            valid_out <= valid_in;
            clipped   <= 1'b0;
            if (valid_in) begin
                i_out   <= shift_sat(i_in, gain_shift);
                q_out   <= shift_sat(q_in, gain_shift);
                clipped <= is_clipped(i_in, gain_shift) || is_clipped(q_in, gain_shift);
            end
        end
    end
endmodule
