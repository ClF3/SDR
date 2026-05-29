`timescale 1ns/1ps

module cordic_sincos #(
    parameter PHASE_WIDTH = 32,
    parameter AMP_WIDTH = 16,
    parameter STAGES = 16
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     valid_in,
    input  wire [PHASE_WIDTH-1:0]   phase,
    output reg                      valid_out,
    output reg signed [AMP_WIDTH-1:0] cos_out,
    output reg signed [AMP_WIDTH-1:0] sin_out
);
    localparam XY_WIDTH = AMP_WIDTH + 4;
    localparam signed [XY_WIDTH-1:0] CORDIC_K = 20'sd19898;

    reg signed [XY_WIDTH-1:0] x_pipe [0:STAGES];
    reg signed [XY_WIDTH-1:0] y_pipe [0:STAGES];
    reg signed [PHASE_WIDTH-1:0] z_pipe [0:STAGES];
    reg [1:0] quadrant_pipe [0:STAGES];
    reg [STAGES:0] valid_pipe;

    integer i;

    function [PHASE_WIDTH-1:0] atan_const;
        input integer idx;
        begin
            case (idx)
                0:  atan_const = 32'h20000000;
                1:  atan_const = 32'h12e4051e;
                2:  atan_const = 32'h09fb385b;
                3:  atan_const = 32'h051111d4;
                4:  atan_const = 32'h028b0d43;
                5:  atan_const = 32'h0145d7e1;
                6:  atan_const = 32'h00a2f61e;
                7:  atan_const = 32'h00517c55;
                8:  atan_const = 32'h0028be53;
                9:  atan_const = 32'h00145f2f;
                10: atan_const = 32'h000a2f98;
                11: atan_const = 32'h000517cc;
                12: atan_const = 32'h00028be6;
                13: atan_const = 32'h000145f3;
                14: atan_const = 32'h0000a2fa;
                15: atan_const = 32'h0000517d;
                default: atan_const = {PHASE_WIDTH{1'b0}};
            endcase
        end
    endfunction

    function signed [AMP_WIDTH-1:0] sat_amp;
        input signed [XY_WIDTH-1:0] value;
        begin
            if (value > 20'sd32767) begin
                sat_amp = 16'sh7fff;
            end else if (value < -20'sd32768) begin
                sat_amp = -16'sd32768;
            end else begin
                sat_amp = value[AMP_WIDTH-1:0];
            end
        end
    endfunction

    wire [1:0] quadrant;
    wire signed [PHASE_WIDTH-1:0] reduced_phase;
    reg signed [XY_WIDTH-1:0] cos_mapped;
    reg signed [XY_WIDTH-1:0] sin_mapped;

    assign quadrant = phase[PHASE_WIDTH-1:PHASE_WIDTH-2];
    assign reduced_phase = {{2{1'b0}}, phase[PHASE_WIDTH-3:0]};

    always @(posedge clk) begin
        if (rst) begin
            valid_pipe <= {(STAGES+1){1'b0}};
            valid_out  <= 1'b0;
            cos_out    <= {AMP_WIDTH{1'b0}};
            sin_out    <= {AMP_WIDTH{1'b0}};
            for (i = 0; i <= STAGES; i = i + 1) begin
                x_pipe[i]        <= {XY_WIDTH{1'b0}};
                y_pipe[i]        <= {XY_WIDTH{1'b0}};
                z_pipe[i]        <= {PHASE_WIDTH{1'b0}};
                quadrant_pipe[i] <= 2'b00;
            end
        end else begin
            valid_pipe[0]    <= valid_in;
            x_pipe[0]        <= CORDIC_K;
            y_pipe[0]        <= {XY_WIDTH{1'b0}};
            z_pipe[0]        <= reduced_phase;
            quadrant_pipe[0] <= quadrant;

            for (i = 0; i < STAGES; i = i + 1) begin
                valid_pipe[i+1]    <= valid_pipe[i];
                quadrant_pipe[i+1] <= quadrant_pipe[i];

                if (!z_pipe[i][PHASE_WIDTH-1]) begin
                    x_pipe[i+1] <= x_pipe[i] - (y_pipe[i] >>> i);
                    y_pipe[i+1] <= y_pipe[i] + (x_pipe[i] >>> i);
                    z_pipe[i+1] <= z_pipe[i] - atan_const(i);
                end else begin
                    x_pipe[i+1] <= x_pipe[i] + (y_pipe[i] >>> i);
                    y_pipe[i+1] <= y_pipe[i] - (x_pipe[i] >>> i);
                    z_pipe[i+1] <= z_pipe[i] + atan_const(i);
                end
            end

            valid_out <= valid_pipe[STAGES];

            case (quadrant_pipe[STAGES])
                2'b00: begin
                    cos_mapped = x_pipe[STAGES];
                    sin_mapped = y_pipe[STAGES];
                end
                2'b01: begin
                    cos_mapped = -y_pipe[STAGES];
                    sin_mapped = x_pipe[STAGES];
                end
                2'b10: begin
                    cos_mapped = -x_pipe[STAGES];
                    sin_mapped = -y_pipe[STAGES];
                end
                default: begin
                    cos_mapped = y_pipe[STAGES];
                    sin_mapped = -x_pipe[STAGES];
                end
            endcase

            cos_out <= sat_amp(cos_mapped);
            sin_out <= sat_amp(sin_mapped);
        end
    end
endmodule
