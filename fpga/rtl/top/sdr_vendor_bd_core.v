`timescale 1ns/1ps

module sdr_vendor_bd_core (
    input  wire        s00_axi_aclk,
    input  wire        s00_axi_aresetn,
    input  wire [31:0] s00_axi_awaddr,
    input  wire [2:0]  s00_axi_awprot,
    input  wire        s00_axi_awvalid,
    output wire        s00_axi_awready,
    input  wire [31:0] s00_axi_wdata,
    input  wire [3:0]  s00_axi_wstrb,
    input  wire        s00_axi_wvalid,
    output wire        s00_axi_wready,
    output wire [1:0]  s00_axi_bresp,
    output wire        s00_axi_bvalid,
    input  wire        s00_axi_bready,
    input  wire [31:0] s00_axi_araddr,
    input  wire [2:0]  s00_axi_arprot,
    input  wire        s00_axi_arvalid,
    output wire        s00_axi_arready,
    output wire [31:0] s00_axi_rdata,
    output wire [1:0]  s00_axi_rresp,
    output wire        s00_axi_rvalid,
    input  wire        s00_axi_rready,

    input  wire        M_AXIS_ACLK,
    input  wire        M_AXIS_FIFO_CLK,
    input  wire        M_AXIS_ARESETN,
    output wire        M_AXIS_TVALID,
    output wire [31:0] M_AXIS_TDATA,
    output wire [3:0]  M_AXIS_TSTRB,
    output wire        M_AXIS_TLAST,
    input  wire        M_AXIS_TREADY,

    input  wire [15:0] din,
    input  wire [31:0] din_comb,
    input  wire        dvalid,

    output wire [31:0] ADC_Speed_Set,
    output wire [1:0]  ChannelSel,
    output wire        ad_sample_en,
    output wire [31:0] reg_conf
);
    localparam CFG_WIDTH = 202;
    localparam IQ_AXIS_WIDTH = 37;

    wire ctrl_rst;
    wire adc_rst;
    wire core_enable_ctrl;
    wire soft_reset_pulse_ctrl;
    wire adc_offset_binary_ctrl;
    wire clear_status_counts_ctrl;
    wire ddc0_enable_ctrl;
    wire ddc0_adc_channel_ctrl;
    wire [31:0] ddc0_freq_word_ctrl;
    wire [15:0] ddc0_decim_rate_ctrl;
    wire [5:0]  ddc0_gain_shift_ctrl;
    wire [63:0] ddc0_frequency_hz_ctrl;
    wire [31:0] ddc0_iq_sample_rate_hz_ctrl;
    wire [31:0] ddc0_bandwidth_hz_ctrl;
    wire signed [15:0] ddc0_gain_db_q8_ctrl;
    wire ddc0_config_changed_ctrl;

    wire [CFG_WIDTH-1:0] cfg_ctrl;
    wire [CFG_WIDTH-1:0] cfg_adc;
    wire cfg_update_adc;
    wire clear_counts_adc;

    wire core_enable_adc;
    wire adc_offset_binary_adc;
    wire ddc0_enable_adc;
    wire ddc0_adc_channel_adc;
    wire [31:0] ddc0_freq_word_adc;
    wire [15:0] ddc0_decim_rate_adc;
    wire [5:0]  ddc0_gain_shift_adc;
    wire [63:0] ddc0_frequency_hz_adc;
    wire [31:0] ddc0_iq_sample_rate_hz_adc;
    wire [31:0] ddc0_bandwidth_hz_adc;
    wire signed [15:0] ddc0_gain_db_q8_adc;

    wire [63:0] adc_timestamp;
    wire [15:0] adc_peak_abs;
    wire [31:0] adc_rms_power;
    wire [31:0] adc_or_count;
    wire [31:0] adc_clip_count;
    wire [31:0] ddc0_sample_count;
    wire [31:0] ddc0_overflow_count;
    wire iq_clip;

    wire [31:0] iq_adc_tdata;
    wire [3:0]  iq_adc_tkeep;
    wire        iq_adc_tvalid;
    wire        iq_adc_tready;
    wire        iq_adc_tlast;
    wire [3:0]  M_AXIS_TKEEP;
    wire [IQ_AXIS_WIDTH-1:0] iq_async_s_tdata;
    wire [IQ_AXIS_WIDTH-1:0] iq_async_m_tdata;

    wire [13:0] adc_ch0_sample_14;
    wire [13:0] adc_ch1_sample_14;

    assign ADC_Speed_Set = 32'd0;
    assign ChannelSel = 2'b11;
    assign ad_sample_en = 1'b1;
    assign reg_conf = 32'd0;

    assign adc_ch0_sample_14 = din_comb[29:16];
    assign adc_ch1_sample_14 = din_comb[13:0];

    assign M_AXIS_TSTRB = M_AXIS_TKEEP;
    assign iq_async_s_tdata = {iq_adc_tlast, iq_adc_tkeep, iq_adc_tdata};
    assign {M_AXIS_TLAST, M_AXIS_TKEEP, M_AXIS_TDATA} = iq_async_m_tdata;

    assign cfg_ctrl = {
        ddc0_gain_db_q8_ctrl,
        ddc0_bandwidth_hz_ctrl,
        ddc0_iq_sample_rate_hz_ctrl,
        ddc0_frequency_hz_ctrl,
        ddc0_gain_shift_ctrl,
        ddc0_decim_rate_ctrl,
        ddc0_freq_word_ctrl,
        ddc0_adc_channel_ctrl,
        ddc0_enable_ctrl,
        adc_offset_binary_ctrl,
        core_enable_ctrl
    };

    assign {
        ddc0_gain_db_q8_adc,
        ddc0_bandwidth_hz_adc,
        ddc0_iq_sample_rate_hz_adc,
        ddc0_frequency_hz_adc,
        ddc0_gain_shift_adc,
        ddc0_decim_rate_adc,
        ddc0_freq_word_adc,
        ddc0_adc_channel_adc,
        ddc0_enable_adc,
        adc_offset_binary_adc,
        core_enable_adc
    } = cfg_adc;

    reset_sync u_ctrl_reset_sync (
        .clk(s00_axi_aclk),
        .arst_n(s00_axi_aresetn),
        .rst(ctrl_rst)
    );

    reset_sync u_adc_reset_sync (
        .clk(M_AXIS_FIFO_CLK),
        .arst_n(M_AXIS_ARESETN),
        .rst(adc_rst)
    );

    axi_lite_slave u_axi_lite_slave (
        .clk(s00_axi_aclk),
        .rst(ctrl_rst),
        .s_axi_awaddr(s00_axi_awaddr),
        .s_axi_awvalid(s00_axi_awvalid),
        .s_axi_awready(s00_axi_awready),
        .s_axi_wdata(s00_axi_wdata),
        .s_axi_wstrb(s00_axi_wstrb),
        .s_axi_wvalid(s00_axi_wvalid),
        .s_axi_wready(s00_axi_wready),
        .s_axi_bresp(s00_axi_bresp),
        .s_axi_bvalid(s00_axi_bvalid),
        .s_axi_bready(s00_axi_bready),
        .s_axi_araddr(s00_axi_araddr),
        .s_axi_arvalid(s00_axi_arvalid),
        .s_axi_arready(s00_axi_arready),
        .s_axi_rdata(s00_axi_rdata),
        .s_axi_rresp(s00_axi_rresp),
        .s_axi_rvalid(s00_axi_rvalid),
        .s_axi_rready(s00_axi_rready),
        .core_enable(core_enable_ctrl),
        .soft_reset_pulse(soft_reset_pulse_ctrl),
        .adc_offset_binary(adc_offset_binary_ctrl),
        .clear_status_counts(clear_status_counts_ctrl),
        .ddc0_enable(ddc0_enable_ctrl),
        .ddc0_adc_channel(ddc0_adc_channel_ctrl),
        .ddc0_freq_word(ddc0_freq_word_ctrl),
        .ddc0_decim_rate(ddc0_decim_rate_ctrl),
        .ddc0_gain_shift(ddc0_gain_shift_ctrl),
        .ddc0_frequency_hz(ddc0_frequency_hz_ctrl),
        .ddc0_iq_sample_rate_hz(ddc0_iq_sample_rate_hz_ctrl),
        .ddc0_bandwidth_hz(ddc0_bandwidth_hz_ctrl),
        .ddc0_gain_db_q8(ddc0_gain_db_q8_ctrl),
        .ddc0_config_changed(ddc0_config_changed_ctrl),
        .adc_locked(1'b1),
        .adc_or(1'b0),
        .adc_peak_abs(adc_peak_abs),
        .adc_rms_power(adc_rms_power),
        .adc_or_count(adc_or_count),
        .adc_clip_count(adc_clip_count),
        .ddc0_sample_count(ddc0_sample_count),
        .ddc0_overflow_count(ddc0_overflow_count)
    );

    config_sync #(
        .WIDTH(CFG_WIDTH)
    ) u_stream_cfg_sync (
        .src_clk(s00_axi_aclk),
        .src_rst(ctrl_rst),
        .src_data(cfg_ctrl),
        .src_update(ddc0_config_changed_ctrl | soft_reset_pulse_ctrl),
        .dst_clk(M_AXIS_FIFO_CLK),
        .dst_rst(adc_rst),
        .dst_data(cfg_adc),
        .dst_update(cfg_update_adc)
    );

    pulse_sync u_clear_counts_sync (
        .src_clk(s00_axi_aclk),
        .src_rst(ctrl_rst),
        .src_pulse(clear_status_counts_ctrl),
        .dst_clk(M_AXIS_FIFO_CLK),
        .dst_rst(adc_rst),
        .dst_pulse(clear_counts_adc)
    );

    sdr_pl_core u_sdr_pl_core (
        .clk(M_AXIS_FIFO_CLK),
        .rst(adc_rst),
        .core_enable(core_enable_adc),
        .clear_status_counts(clear_counts_adc),
        .adc_offset_binary(adc_offset_binary_adc),
        .adc_ch0_sample_14(adc_ch0_sample_14),
        .adc_ch1_sample_14(adc_ch1_sample_14),
        .adc_sample_valid(dvalid),
        .adc_or(1'b0),
        .adc_locked(1'b1),
        .ddc0_enable(ddc0_enable_adc),
        .ddc0_adc_channel(ddc0_adc_channel_adc),
        .ddc0_config_changed(cfg_update_adc),
        .ddc0_freq_word(ddc0_freq_word_adc),
        .ddc0_decim_rate(ddc0_decim_rate_adc),
        .ddc0_gain_shift(ddc0_gain_shift_adc),
        .ddc0_frequency_hz(ddc0_frequency_hz_adc),
        .ddc0_iq_sample_rate_hz(ddc0_iq_sample_rate_hz_adc),
        .ddc0_bandwidth_hz(ddc0_bandwidth_hz_adc),
        .ddc0_gain_db_q8(ddc0_gain_db_q8_adc),
        .m_axis_iq_tdata(iq_adc_tdata),
        .m_axis_iq_tkeep(iq_adc_tkeep),
        .m_axis_iq_tvalid(iq_adc_tvalid),
        .m_axis_iq_tready(iq_adc_tready),
        .m_axis_iq_tlast(iq_adc_tlast),
        .adc_timestamp(adc_timestamp),
        .adc_peak_abs(adc_peak_abs),
        .adc_rms_power(adc_rms_power),
        .adc_or_count(adc_or_count),
        .adc_clip_count(adc_clip_count),
        .ddc0_sample_count(ddc0_sample_count),
        .ddc0_overflow_count(ddc0_overflow_count),
        .iq_clip(iq_clip)
    );

    axis_async_fifo #(
        .WIDTH(IQ_AXIS_WIDTH),
        .ADDR_WIDTH(10)
    ) u_iq_axis_cdc_fifo (
        .s_clk(M_AXIS_FIFO_CLK),
        .s_rst(adc_rst),
        .s_tdata(iq_async_s_tdata),
        .s_tvalid(iq_adc_tvalid),
        .s_tready(iq_adc_tready),
        .m_clk(M_AXIS_ACLK),
        .m_rst(~M_AXIS_ARESETN),
        .m_tdata(iq_async_m_tdata),
        .m_tvalid(M_AXIS_TVALID),
        .m_tready(M_AXIS_TREADY)
    );
endmodule
