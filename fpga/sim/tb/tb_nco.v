`timescale 1ns/1ps

module tb_nco;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg enable = 1'b0;
    reg sample_valid = 1'b0;
    wire trig_valid;
    wire signed [15:0] cos_out;
    wire signed [15:0] sin_out;
    integer valid_count = 0;

    always #5 clk = ~clk;

    nco #(
        .PHASE_WIDTH(32),
        .AMP_WIDTH(16),
        .CORDIC_STAGES(16)
    ) dut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .sample_valid(sample_valid),
        .freq_word(32'h4000_0000),
        .trig_valid(trig_valid),
        .cos_out(cos_out),
        .sin_out(sin_out)
    );

    always @(posedge clk) begin
        if (trig_valid) begin
            valid_count <= valid_count + 1;
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        rst = 1'b0;
        enable = 1'b1;
        sample_valid = 1'b1;
        repeat (80) @(posedge clk);

        if (valid_count < 32) begin
            $display("FAIL: NCO valid_count=%0d", valid_count);
            $finish(1);
        end

        $display("PASS: tb_nco valid_count=%0d last_cos=%0d last_sin=%0d", valid_count, cos_out, sin_out);
        $finish;
    end
endmodule
