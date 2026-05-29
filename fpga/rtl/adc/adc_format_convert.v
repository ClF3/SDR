`timescale 1ns/1ps

module adc_format_convert #(
    parameter ADC_WIDTH = 14,
    parameter OUT_WIDTH = 16
) (
    input  wire [ADC_WIDTH-1:0] adc_sample,
    input  wire                 offset_binary,
    output wire signed [OUT_WIDTH-1:0] sample_signed
);
    wire [ADC_WIDTH-1:0] twos_bits;
    wire signed [ADC_WIDTH-1:0] twos_sample;

    assign twos_bits   = offset_binary ? {~adc_sample[ADC_WIDTH-1], adc_sample[ADC_WIDTH-2:0]} : adc_sample;
    assign twos_sample = twos_bits;
    assign sample_signed = {{(OUT_WIDTH-ADC_WIDTH){twos_sample[ADC_WIDTH-1]}}, twos_sample};
endmodule
