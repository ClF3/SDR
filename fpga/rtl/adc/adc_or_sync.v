`timescale 1ns/1ps

module adc_or_sync (
    input  wire clk,
    input  wire rst,
    input  wire adc_or_async,
    output wire adc_or_sync
);
    sync_2ff #(.WIDTH(1)) u_sync_2ff (
        .clk(clk),
        .rst(rst),
        .async_in(adc_or_async),
        .sync_out(adc_or_sync)
    );
endmodule
