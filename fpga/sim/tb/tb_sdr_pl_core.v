`timescale 1ns/1ps

module tb_sdr_pl_core;
    localparam real FS_HZ = 250000000.0;
    localparam real TONE_HZ = 10000000.0;
    localparam [15:0] DECIM = 16'd50;
    localparam [31:0] FREQ_WORD = 32'd171798692;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg core_enable = 1'b0;
    reg clear_status_counts = 1'b0;
    reg [13:0] adc_sample_14 = 14'd0;
    reg adc_sample_valid = 1'b0;
    reg adc_or = 1'b0;
    reg adc_locked = 1'b1;
    wire [31:0] m_axis_iq_tdata;
    wire [3:0] m_axis_iq_tkeep;
    wire m_axis_iq_tvalid;
    reg  m_axis_iq_tready = 1'b1;
    wire m_axis_iq_tlast;
    wire [63:0] adc_timestamp;
    wire [15:0] adc_peak_abs;
    wire [31:0] adc_rms_power;
    wire [31:0] adc_or_count;
    wire [31:0] adc_clip_count;
    wire [31:0] ddc0_sample_count;
    wire [31:0] ddc0_overflow_count;
    wire iq_clip;
    integer out_count = 0;
    integer signed sample_tmp;
    real phase = 0.0;
    real step;

    always #2 clk = ~clk;

    sdr_pl_core dut (
        .clk(clk),
        .rst(rst),
        .core_enable(core_enable),
        .clear_status_counts(clear_status_counts),
        .adc_offset_binary(1'b0),
        .adc_ch0_sample_14(adc_sample_14),
        .adc_ch1_sample_14(14'd0),
        .adc_sample_valid(adc_sample_valid),
        .adc_or(adc_or),
        .adc_locked(adc_locked),
        .ddc0_enable(1'b1),
        .ddc0_adc_channel(1'b0),
        .ddc0_config_changed(1'b0),
        .ddc0_freq_word(FREQ_WORD),
        .ddc0_decim_rate(DECIM),
        .ddc0_gain_shift(6'd25),
        .ddc0_frequency_hz(64'd10000000),
        .ddc0_iq_sample_rate_hz(32'd5000000),
        .ddc0_bandwidth_hz(32'd250000),
        .ddc0_gain_db_q8(16'sd0),
        .m_axis_iq_tdata(m_axis_iq_tdata),
        .m_axis_iq_tkeep(m_axis_iq_tkeep),
        .m_axis_iq_tvalid(m_axis_iq_tvalid),
        .m_axis_iq_tready(m_axis_iq_tready),
        .m_axis_iq_tlast(m_axis_iq_tlast),
        .adc_timestamp(adc_timestamp),
        .adc_peak_abs(adc_peak_abs),
        .adc_rms_power(adc_rms_power),
        .adc_or_count(adc_or_count),
        .adc_clip_count(adc_clip_count),
        .ddc0_sample_count(ddc0_sample_count),
        .ddc0_overflow_count(ddc0_overflow_count),
        .iq_clip(iq_clip)
    );

    always @(posedge clk) begin
        if (!rst && adc_sample_valid) begin
            sample_tmp = $rtoi(6000.0 * $sin(phase));
            adc_sample_14 <= sample_tmp[13:0];
            phase <= phase + step;
        end

        if (m_axis_iq_tvalid && m_axis_iq_tready) begin
            out_count <= out_count + 1;
        end
    end

    initial begin
        step = 2.0 * 3.14159265358979323846 * TONE_HZ / FS_HZ;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        core_enable = 1'b1;
        adc_sample_valid = 1'b1;
        repeat (20000) @(posedge clk);
        adc_sample_valid = 1'b0;
        repeat (20) @(posedge clk);

        if (out_count < 200 || adc_timestamp == 0 || ddc0_overflow_count != 0 || m_axis_iq_tkeep != 4'hf) begin
            $display("FAIL: out=%0d timestamp=%0d overflow=%0d", out_count, adc_timestamp, ddc0_overflow_count);
            $finish(1);
        end

        $display("PASS: tb_sdr_pl_core outputs=%0d timestamp=%0d peak=%0d", out_count, adc_timestamp, adc_peak_abs);
        $finish;
    end
endmodule
