`timescale 1ns/1ps

module adc_sample_unpack #(
    parameter DATA_WIDTH = 14
) (
    input  wire [DATA_WIDTH-1:0] raw_sample,
    output wire [DATA_WIDTH-1:0] adc_sample
);
    assign adc_sample = raw_sample;
endmodule
