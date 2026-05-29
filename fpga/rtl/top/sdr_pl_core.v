`timescale 1ns/1ps

module sdr_pl_core #(
    parameter ADC_WIDTH = 14,
    parameter SAMPLE_WIDTH = 16
) (
    input  wire                         clk,
    input  wire                         rst,

    input  wire                         core_enable,
    input  wire                         clear_status_counts,
    input  wire                         adc_offset_binary,

    input  wire [ADC_WIDTH-1:0]         adc_ch0_sample_14,
    input  wire [ADC_WIDTH-1:0]         adc_ch1_sample_14,
    input  wire                         adc_sample_valid,
    input  wire                         adc_or,
    input  wire                         adc_locked,

    input  wire                         ddc0_enable,
    input  wire                         ddc0_adc_channel,
    input  wire                         ddc0_config_changed,
    input  wire [31:0]                  ddc0_freq_word,
    input  wire [15:0]                  ddc0_decim_rate,
    input  wire [5:0]                   ddc0_gain_shift,
    input  wire [63:0]                  ddc0_frequency_hz,
    input  wire [31:0]                  ddc0_iq_sample_rate_hz,
    input  wire [31:0]                  ddc0_bandwidth_hz,
    input  wire signed [15:0]           ddc0_gain_db_q8,

    output wire [31:0]                  m_axis_iq_tdata,
    output wire [3:0]                   m_axis_iq_tkeep,
    output wire                         m_axis_iq_tvalid,
    input  wire                         m_axis_iq_tready,
    output wire                         m_axis_iq_tlast,

    output wire [63:0]                  adc_timestamp,
    output wire [15:0]                  adc_peak_abs,
    output wire [31:0]                  adc_rms_power,
    output wire [31:0]                  adc_or_count,
    output wire [31:0]                  adc_clip_count,
    output wire [31:0]                  ddc0_sample_count,
    output wire [31:0]                  ddc0_overflow_count,
    output wire                         iq_clip
);
    wire [ADC_WIDTH-1:0] adc_sample_14;
    wire signed [SAMPLE_WIDTH-1:0] adc_signed;
    wire signed [SAMPLE_WIDTH-1:0] adc_dc_removed;
    wire                           adc_dc_valid;
    wire                           adc_active_valid;
    wire [31:0]                    ddc_raw_tdata;
    wire                           ddc_raw_tvalid;
    wire                           ddc_raw_tready;
    wire [15:0]                    packet_flags;
    wire [31:0]                    iq_packet_seq;
    wire [31:0]                    iq_packet_count;
    reg                            adc_or_seen;
    reg                            iq_overflow_seen;
    reg  [31:0]                    ddc0_overflow_count_d;
    reg  [31:0]                    iq_packet_count_d;

    assign adc_sample_14 = ddc0_adc_channel ? adc_ch1_sample_14 : adc_ch0_sample_14;
    assign adc_active_valid = adc_sample_valid && core_enable && adc_locked;
    assign packet_flags = {14'd0, iq_overflow_seen, adc_or_seen};

    adc_format_convert #(
        .ADC_WIDTH(ADC_WIDTH),
        .OUT_WIDTH(SAMPLE_WIDTH)
    ) u_adc_format_convert (
        .adc_sample(adc_sample_14),
        .offset_binary(adc_offset_binary),
        .sample_signed(adc_signed)
    );

    dc_offset_remove #(
        .WIDTH(SAMPLE_WIDTH),
        .AVG_SHIFT(12)
    ) u_dc_offset_remove (
        .clk(clk),
        .rst(rst),
        .enable(1'b1),
        .sample_in(adc_signed),
        .sample_valid_in(adc_active_valid),
        .sample_out(adc_dc_removed),
        .sample_valid_out(adc_dc_valid)
    );

    adc_level_monitor #(
        .WIDTH(SAMPLE_WIDTH),
        .WINDOW_LOG2(16)
    ) u_adc_level_monitor (
        .clk(clk),
        .rst(rst),
        .clear_counts(clear_status_counts),
        .sample_in(adc_signed),
        .sample_valid(adc_active_valid),
        .adc_or(adc_or),
        .extra_clip(iq_clip),
        .peak_abs(adc_peak_abs),
        .rms_power(adc_rms_power),
        .or_count(adc_or_count),
        .clip_count(adc_clip_count)
    );

    timestamp_counter u_timestamp_counter (
        .clk(clk),
        .rst(rst),
        .sample_valid(adc_active_valid),
        .timestamp(adc_timestamp)
    );

    ddc_core #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .PHASE_WIDTH(32),
        .TRIG_WIDTH(16),
        .MIX_WIDTH(32),
        .CIC_WIDTH(56),
        .CORDIC_STAGES(16),
        .USE_FIR(0)
    ) u_ddc0 (
        .clk(clk),
        .rst(rst),
        .enable(core_enable && ddc0_enable),
        .sample_in(adc_dc_removed),
        .sample_valid(adc_dc_valid),
        .freq_word(ddc0_freq_word),
        .decim_rate(ddc0_decim_rate),
        .gain_shift(ddc0_gain_shift),
        .m_axis_tdata(ddc_raw_tdata),
        .m_axis_tvalid(ddc_raw_tvalid),
        .m_axis_tready(ddc_raw_tready),
        .overflow_count(ddc0_overflow_count),
        .sample_count(ddc0_sample_count),
        .iq_clip(iq_clip)
    );

    always @(posedge clk) begin
        if (rst) begin
            adc_or_seen           <= 1'b0;
            iq_overflow_seen      <= 1'b0;
            ddc0_overflow_count_d <= 32'd0;
            iq_packet_count_d     <= 32'd0;
        end else begin
            ddc0_overflow_count_d <= ddc0_overflow_count;
            iq_packet_count_d     <= iq_packet_count;

            if (iq_packet_count != iq_packet_count_d) begin
                adc_or_seen      <= adc_or;
                iq_overflow_seen <= (ddc0_overflow_count != ddc0_overflow_count_d);
            end else begin
                if (adc_or) begin
                    adc_or_seen <= 1'b1;
                end
                if (ddc0_overflow_count != ddc0_overflow_count_d) begin
                    iq_overflow_seen <= 1'b1;
                end
            end
        end
    end

    iq_packetizer #(
        .STREAM_ID(16'd0),
        .FRAME_SAMPLES(16'd256)
    ) u_iq_packetizer (
        .clk(clk),
        .rst(rst),
        .enable(core_enable && ddc0_enable),
        .config_changed(ddc0_config_changed),
        .s_axis_tdata(ddc_raw_tdata),
        .s_axis_tvalid(ddc_raw_tvalid),
        .s_axis_tready(ddc_raw_tready),
        .adc_timestamp_seed(adc_timestamp),
        .frequency_hz(ddc0_frequency_hz),
        .iq_sample_rate_hz(ddc0_iq_sample_rate_hz),
        .bandwidth_hz(ddc0_bandwidth_hz),
        .flags(packet_flags),
        .gain_db_q8(ddc0_gain_db_q8),
        .decimation({16'd0, ddc0_decim_rate}),
        .m_axis_tdata(m_axis_iq_tdata),
        .m_axis_tkeep(m_axis_iq_tkeep),
        .m_axis_tvalid(m_axis_iq_tvalid),
        .m_axis_tready(m_axis_iq_tready),
        .m_axis_tlast(m_axis_iq_tlast),
        .packet_seq(iq_packet_seq),
        .packet_count(iq_packet_count)
    );
endmodule
