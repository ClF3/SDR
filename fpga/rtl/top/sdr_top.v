`timescale 1ns/1ps

module sdr_top (
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    input  wire        adc_ref_clk,
    input  wire        spi_clk_50m,
    input  wire        reset_n_0,

    input  wire        adc1_clk_n_0,
    input  wire        adc1_clk_p_0,
    input  wire [13:0] adc1_data_n_0,
    input  wire [13:0] adc1_data_p_0,
    output wire        adc1_spi_ce_0,
    inout  wire        adc1_spi_io_0,
    output wire        adc1_spi_sclk_0,
    output wire        adc_clk_n_0,
    output wire        adc_clk_p_0,

    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    output wire [31:0] m_axis_iq_tdata,
    output wire [3:0]  m_axis_iq_tkeep,
    output wire        m_axis_iq_tvalid,
    input  wire        m_axis_iq_tready,
    output wire        m_axis_iq_tlast
);
    localparam CFG_WIDTH = 202;
    localparam IQ_AXIS_WIDTH = 37;

    wire ctrl_rst;
    wire adc_rst;
    wire adc_sample_clk;
    wire [13:0] adc_ch0_sample_14;
    wire [13:0] adc_ch1_sample_14;
    wire        adc_sample_valid;
    wire        adc_locked;

    wire        core_enable_ctrl;
    wire        soft_reset_pulse_ctrl;
    wire        adc_offset_binary_ctrl;
    wire        clear_status_counts_ctrl;
    wire        ddc0_enable_ctrl;
    wire        ddc0_adc_channel_ctrl;
    wire [31:0] ddc0_freq_word_ctrl;
    wire [15:0] ddc0_decim_rate_ctrl;
    wire [5:0]  ddc0_gain_shift_ctrl;
    wire [63:0] ddc0_frequency_hz_ctrl;
    wire [31:0] ddc0_iq_sample_rate_hz_ctrl;
    wire [31:0] ddc0_bandwidth_hz_ctrl;
    wire signed [15:0] ddc0_gain_db_q8_ctrl;
    wire        ddc0_config_changed_ctrl;

    wire [CFG_WIDTH-1:0] cfg_ctrl;
    wire [CFG_WIDTH-1:0] cfg_adc;
    wire                 cfg_update_adc;
    wire                 clear_counts_adc;

    wire        core_enable_adc;
    wire        adc_offset_binary_adc;
    wire        ddc0_enable_adc;
    wire        ddc0_adc_channel_adc;
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
    wire        iq_clip;
    wire        adc_or_tied_off;
    wire [31:0] iq_adc_tdata;
    wire [3:0]  iq_adc_tkeep;
    wire        iq_adc_tvalid;
    wire        iq_adc_tready;
    wire        iq_adc_tlast;
    wire [IQ_AXIS_WIDTH-1:0] iq_async_s_tdata;
    wire [IQ_AXIS_WIDTH-1:0] iq_async_m_tdata;

    assign adc_locked = adc_sample_valid;
    assign adc_or_tied_off = 1'b0;
    assign iq_async_s_tdata = {iq_adc_tlast, iq_adc_tkeep, iq_adc_tdata};
    assign {m_axis_iq_tlast, m_axis_iq_tkeep, m_axis_iq_tdata} = iq_async_m_tdata;

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
        .clk(s_axi_aclk),
        .arst_n(s_axi_aresetn & reset_n_0),
        .rst(ctrl_rst)
    );

    reset_sync u_adc_reset_sync (
        .clk(adc_sample_clk),
        .arst_n(reset_n_0),
        .rst(adc_rst)
    );

    acfl3432_adc_frontend u_acfl3432_adc_frontend (
        .adc_ref_clk(adc_ref_clk),
        .adc_reset(adc_rst),
        .adc1_clk_p(adc1_clk_p_0),
        .adc1_clk_n(adc1_clk_n_0),
        .adc1_data_p(adc1_data_p_0),
        .adc1_data_n(adc1_data_n_0),
        .adc_clk_p(adc_clk_p_0),
        .adc_clk_n(adc_clk_n_0),
        .adc_sample_clk(adc_sample_clk),
        .adc_ch0_sample_14(adc_ch0_sample_14),
        .adc_ch1_sample_14(adc_ch1_sample_14),
        .adc_sample_valid(adc_sample_valid)
    );

    acfl3432_spi_config u_acfl3432_spi_config (
        .clk_50m(spi_clk_50m),
        .rst_n(reset_n_0),
        .conf_en(1'b0),
        .reg_conf(32'd0),
        .adc_spi_ce(adc1_spi_ce_0),
        .adc_spi_sclk(adc1_spi_sclk_0),
        .adc_spi_io(adc1_spi_io_0)
    );

    axi_lite_slave u_axi_lite_slave (
        .clk(s_axi_aclk),
        .rst(ctrl_rst),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
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
        .adc_locked(adc_locked),
        .adc_or(adc_or_tied_off),
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
        .src_clk(s_axi_aclk),
        .src_rst(ctrl_rst),
        .src_data(cfg_ctrl),
        .src_update(ddc0_config_changed_ctrl | soft_reset_pulse_ctrl),
        .dst_clk(adc_sample_clk),
        .dst_rst(adc_rst),
        .dst_data(cfg_adc),
        .dst_update(cfg_update_adc)
    );

    pulse_sync u_clear_counts_sync (
        .src_clk(s_axi_aclk),
        .src_rst(ctrl_rst),
        .src_pulse(clear_status_counts_ctrl),
        .dst_clk(adc_sample_clk),
        .dst_rst(adc_rst),
        .dst_pulse(clear_counts_adc)
    );

    sdr_pl_core u_sdr_pl_core (
        .clk(adc_sample_clk),
        .rst(adc_rst),
        .core_enable(core_enable_adc),
        .clear_status_counts(clear_counts_adc),
        .adc_offset_binary(adc_offset_binary_adc),
        .adc_ch0_sample_14(adc_ch0_sample_14),
        .adc_ch1_sample_14(adc_ch1_sample_14),
        .adc_sample_valid(adc_sample_valid),
        .adc_or(adc_or_tied_off),
        .adc_locked(adc_locked),
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
        .s_clk(adc_sample_clk),
        .s_rst(adc_rst),
        .s_tdata(iq_async_s_tdata),
        .s_tvalid(iq_adc_tvalid),
        .s_tready(iq_adc_tready),
        .m_clk(s_axi_aclk),
        .m_rst(ctrl_rst),
        .m_tdata(iq_async_m_tdata),
        .m_tvalid(m_axis_iq_tvalid),
        .m_tready(m_axis_iq_tready)
    );
endmodule
