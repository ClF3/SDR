`timescale 1ns/1ps

module tb_adc_level_monitor;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg clear_counts = 1'b0;
    reg signed [15:0] sample_in = 16'sd0;
    reg sample_valid = 1'b0;
    reg adc_or = 1'b0;
    wire [15:0] peak_abs;
    wire [31:0] rms_power;
    wire [31:0] or_count;
    wire [31:0] clip_count;
    integer i;

    always #5 clk = ~clk;

    adc_level_monitor #(
        .WIDTH(16),
        .WINDOW_LOG2(4),
        .CLIP_LEVEL(16'sh7000)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear_counts(clear_counts),
        .sample_in(sample_in),
        .sample_valid(sample_valid),
        .adc_or(adc_or),
        .extra_clip(1'b0),
        .peak_abs(peak_abs),
        .rms_power(rms_power),
        .or_count(or_count),
        .clip_count(clip_count)
    );

    initial begin
        repeat (4) @(posedge clk);
        rst = 1'b0;
        sample_valid = 1'b1;

        for (i = 0; i < 32; i = i + 1) begin
            @(negedge clk);
            sample_in = (i == 7) ? 16'sh7100 : i * 16'sd100;
            adc_or = (i == 5) || (i == 6);
            @(posedge clk);
        end

        sample_valid = 1'b0;
        adc_or = 1'b0;
        repeat (4) @(posedge clk);

        if (peak_abs == 16'd0 || rms_power == 32'd0 || or_count == 32'd0 || clip_count == 32'd0) begin
            $display("FAIL: peak=%0d rms=%0d or=%0d clip=%0d", peak_abs, rms_power, or_count, clip_count);
            $finish(1);
        end

        $display("PASS: tb_adc_level_monitor peak=%0d rms=%0d or=%0d clip=%0d", peak_abs, rms_power, or_count, clip_count);
        $finish;
    end
endmodule
