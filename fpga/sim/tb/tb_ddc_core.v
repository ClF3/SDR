`timescale 1ns/1ps

module tb_ddc_core;
    localparam real FS_HZ = 250000000.0;
    localparam real TONE_HZ = 10000000.0;
    localparam [15:0] DECIM = 16'd50;
    localparam [31:0] FREQ_WORD = 32'd171798692; // round(10e6 / 250e6 * 2^32)

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg enable = 1'b0;
    reg signed [15:0] sample_in = 16'sd0;
    reg sample_valid = 1'b0;
    wire [31:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg  m_axis_tready = 1'b1;
    wire [31:0] overflow_count;
    wire [31:0] sample_count;
    wire iq_clip;
    integer n = 0;
    integer out_count = 0;
    real phase = 0.0;
    real step;

    always #2 clk = ~clk;

    ddc_core #(
        .SAMPLE_WIDTH(16),
        .PHASE_WIDTH(32),
        .TRIG_WIDTH(16),
        .MIX_WIDTH(32),
        .CIC_WIDTH(56),
        .CORDIC_STAGES(16),
        .USE_FIR(0)
    ) dut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .sample_in(sample_in),
        .sample_valid(sample_valid),
        .freq_word(FREQ_WORD),
        .decim_rate(DECIM),
        .gain_shift(6'd25),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .overflow_count(overflow_count),
        .sample_count(sample_count),
        .iq_clip(iq_clip)
    );

    always @(posedge clk) begin
        if (!rst && sample_valid) begin
            sample_in <= $rtoi(8000.0 * $sin(phase));
            phase <= phase + step;
            n <= n + 1;
        end

        if (m_axis_tvalid && m_axis_tready) begin
            out_count <= out_count + 1;
        end
    end

    initial begin
        step = 2.0 * 3.14159265358979323846 * TONE_HZ / FS_HZ;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        enable = 1'b1;
        sample_valid = 1'b1;
        repeat (20000) @(posedge clk);
        sample_valid = 1'b0;
        repeat (20) @(posedge clk);

        if (out_count < 200 || overflow_count != 0) begin
            $display("FAIL: out_count=%0d overflow=%0d clip=%0b", out_count, overflow_count, iq_clip);
            $finish(1);
        end

        $display("PASS: tb_ddc_core outputs=%0d last_iq=0x%08x", out_count, m_axis_tdata);
        $finish;
    end
endmodule
