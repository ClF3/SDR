`timescale 1ns/1ps

module adc_if_cm3432 #(
    parameter DATA_WIDTH = 14
) (
    input  wire                  clk,
    input  wire                  rst,

    input  wire [DATA_WIDTH-1:0] adc_parallel_data,
    input  wire                  adc_parallel_valid,
    input  wire                  adc_or_async,

    output wire [DATA_WIDTH-1:0] sample_14,
    output wire                  sample_valid,
    output wire                  adc_or,
    output wire                  adc_locked
);
    wire [DATA_WIDTH-1:0] unpacked_sample;

    adc_sample_unpack #(.DATA_WIDTH(DATA_WIDTH)) u_unpack (
        .raw_sample(adc_parallel_data),
        .adc_sample(unpacked_sample)
    );

    adc_bitslip_align #(.DATA_WIDTH(DATA_WIDTH)) u_align (
        .clk(clk),
        .rst(rst),
        .sample_in(unpacked_sample),
        .sample_valid_in(adc_parallel_valid),
        .sample_out(sample_14),
        .sample_valid_out(sample_valid),
        .locked(adc_locked)
    );

    adc_or_sync u_adc_or_sync (
        .clk(clk),
        .rst(rst),
        .adc_or_async(adc_or_async),
        .adc_or_sync(adc_or)
    );
endmodule
