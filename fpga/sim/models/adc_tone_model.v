`timescale 1ns/1ps

module adc_tone_model #(
    parameter ADC_WIDTH = 14,
    parameter integer AMPLITUDE = 6000
) (
    input  wire clk,
    input  wire rst,
    input  wire enable,
    output reg  [ADC_WIDTH-1:0] sample,
    output reg                  valid
);
    real phase;
    real step;
    integer signed sample_tmp;

    initial begin
        phase = 0.0;
        step = 2.0 * 3.14159265358979323846 * 10000000.0 / 250000000.0;
    end

    always @(posedge clk) begin
        if (rst) begin
            sample <= {ADC_WIDTH{1'b0}};
            valid  <= 1'b0;
            phase  <= 0.0;
        end else begin
            valid <= enable;
            if (enable) begin
                sample_tmp = $rtoi(AMPLITUDE * $sin(phase));
                sample <= sample_tmp[ADC_WIDTH-1:0];
                phase <= phase + step;
            end
        end
    end
endmodule
