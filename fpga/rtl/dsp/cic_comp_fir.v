`timescale 1ns/1ps

module cic_comp_fir #(
    parameter DATA_WIDTH = 56,
    parameter COEF_WIDTH = 16,
    parameter TAPS = 17
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire signed [DATA_WIDTH-1:0] sample_in,
    input  wire                         valid_in,
    output reg  signed [DATA_WIDTH-1:0] sample_out,
    output reg                          valid_out
);
    reg signed [DATA_WIDTH-1:0] shift_reg [0:TAPS-1];
    reg signed [DATA_WIDTH+COEF_WIDTH+5:0] acc;
    integer i;

    function signed [COEF_WIDTH-1:0] coef;
        input integer idx;
        begin
            case (idx)
                0:  coef = 16'sd0;
                1:  coef = -16'sd97;
                2:  coef = 16'sd0;
                3:  coef = 16'sd563;
                4:  coef = 16'sd0;
                5:  coef = -16'sd1974;
                6:  coef = 16'sd0;
                7:  coef = 16'sd10122;
                8:  coef = 16'sd16384;
                9:  coef = 16'sd10122;
                10: coef = 16'sd0;
                11: coef = -16'sd1974;
                12: coef = 16'sd0;
                13: coef = 16'sd563;
                14: coef = 16'sd0;
                15: coef = -16'sd97;
                default: coef = 16'sd0;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < TAPS; i = i + 1) begin
                shift_reg[i] <= {DATA_WIDTH{1'b0}};
            end
            acc        <= {(DATA_WIDTH+COEF_WIDTH+6){1'b0}};
            sample_out <= {DATA_WIDTH{1'b0}};
            valid_out  <= 1'b0;
        end else begin
            valid_out <= valid_in;

            if (valid_in) begin
                shift_reg[0] <= sample_in;
                for (i = 1; i < TAPS; i = i + 1) begin
                    shift_reg[i] <= shift_reg[i-1];
                end

                acc = {(DATA_WIDTH+COEF_WIDTH+6){1'b0}};
                for (i = 0; i < TAPS; i = i + 1) begin
                    acc = acc + shift_reg[i] * coef(i);
                end
                sample_out <= acc >>> 15;
            end
        end
    end
endmodule
