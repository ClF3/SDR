`timescale 1ns/1ps

module nco #(
    parameter PHASE_WIDTH = 32,
    parameter AMP_WIDTH = 16,
    parameter CORDIC_STAGES = 16
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         enable,
    input  wire                         sample_valid,
    input  wire [PHASE_WIDTH-1:0]       freq_word,
    output wire                         trig_valid,
    output wire signed [AMP_WIDTH-1:0]  cos_out,
    output wire signed [AMP_WIDTH-1:0]  sin_out
);
    reg [PHASE_WIDTH-1:0] phase_acc;
    wire advance;

    assign advance = enable && sample_valid;

    always @(posedge clk) begin
        if (rst) begin
            phase_acc <= {PHASE_WIDTH{1'b0}};
        end else if (advance) begin
            phase_acc <= phase_acc + freq_word;
        end
    end

    cordic_sincos #(
        .PHASE_WIDTH(PHASE_WIDTH),
        .AMP_WIDTH(AMP_WIDTH),
        .STAGES(CORDIC_STAGES)
    ) u_cordic_sincos (
        .clk(clk),
        .rst(rst),
        .valid_in(advance),
        .phase(phase_acc),
        .valid_out(trig_valid),
        .cos_out(cos_out),
        .sin_out(sin_out)
    );
endmodule
