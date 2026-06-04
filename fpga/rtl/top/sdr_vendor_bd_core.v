`timescale 1ns/1ps

module sdr_vendor_bd_core (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S00_AXI_CLK, ASSOCIATED_BUSIF S00_AXI, ASSOCIATED_RESET s00_axi_aresetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 S00_AXI_CLK CLK" *)
    input  wire        s00_axi_aclk,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S00_AXI_RST, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 S00_AXI_RST RST" *)
    input  wire        s00_axi_aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWADDR" *)
    input  wire [31:0] s00_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWPROT" *)
    input  wire [2:0]  s00_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWVALID" *)
    input  wire        s00_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWREADY" *)
    output wire        s00_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI WDATA" *)
    input  wire [31:0] s00_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI WSTRB" *)
    input  wire [3:0]  s00_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI WVALID" *)
    input  wire        s00_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI WREADY" *)
    output wire        s00_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI BRESP" *)
    output wire [1:0]  s00_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI BVALID" *)
    output wire        s00_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI BREADY" *)
    input  wire        s00_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARADDR" *)
    input  wire [31:0] s00_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARPROT" *)
    input  wire [2:0]  s00_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARVALID" *)
    input  wire        s00_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARREADY" *)
    output wire        s00_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RDATA" *)
    output wire [31:0] s00_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RRESP" *)
    output wire [1:0]  s00_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RVALID" *)
    output wire        s00_axi_rvalid,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S00_AXI, DATA_WIDTH 32, ADDR_WIDTH 32, PROTOCOL AXI4LITE, READ_WRITE_MODE READ_WRITE" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RREADY" *)
    input  wire        s00_axi_rready,

    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS_CLK, ASSOCIATED_BUSIF M_AXIS, ASSOCIATED_RESET M_AXIS_ARESETN" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 M_AXIS_CLK CLK" *)
    input  wire        M_AXIS_ACLK,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 M_AXIS_FIFO_CLK CLK" *)
    input  wire        M_AXIS_FIFO_CLK,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS_RST, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 M_AXIS_RST RST" *)
    input  wire        M_AXIS_ARESETN,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire        M_AXIS_TVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [31:0] M_AXIS_TDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TSTRB" *)
    output wire [3:0]  M_AXIS_TSTRB,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire        M_AXIS_TLAST,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS, TDATA_NUM_BYTES 4, HAS_TLAST 1, HAS_TSTRB 1" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
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
    localparam SYNTHETIC_ADC_SOURCE = 1'b0;

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
    wire [31:0] adc_debug_flags;
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
    reg  [31:0] adc_dvalid_count;
    reg  [31:0] adc_cfg_update_count;
    reg  [13:0] synthetic_sample;

    wire        sdr_clk;
    wire        sdr_rst;
    wire        sdr_clear_counts;
    wire        sdr_core_enable;
    wire        sdr_adc_offset_binary;
    wire        sdr_ddc0_enable;
    wire        sdr_ddc0_adc_channel;
    wire [31:0] sdr_ddc0_freq_word;
    wire [15:0] sdr_ddc0_decim_rate;
    wire [5:0]  sdr_ddc0_gain_shift;
    wire [63:0] sdr_ddc0_frequency_hz;
    wire [31:0] sdr_ddc0_iq_sample_rate_hz;
    wire [31:0] sdr_ddc0_bandwidth_hz;
    wire signed [15:0] sdr_ddc0_gain_db_q8;
    wire        sdr_ddc0_config_changed;
    wire [13:0] sdr_adc_ch0_sample_14;
    wire [13:0] sdr_adc_ch1_sample_14;
    wire        sdr_adc_sample_valid;

    assign ADC_Speed_Set = 32'd0;
    assign ChannelSel = 2'b11;
    assign ad_sample_en = 1'b1;
    assign reg_conf = 32'd0;

    assign adc_ch0_sample_14 = din_comb[29:16];
    assign adc_ch1_sample_14 = din_comb[13:0];

    assign M_AXIS_TSTRB = M_AXIS_TKEEP;
    assign iq_async_s_tdata = {iq_adc_tlast, iq_adc_tkeep, iq_adc_tdata};
    assign {M_AXIS_TLAST, M_AXIS_TKEEP, M_AXIS_TDATA} = iq_async_m_tdata;
    assign sdr_clk = SYNTHETIC_ADC_SOURCE ? M_AXIS_ACLK : M_AXIS_FIFO_CLK;
    assign sdr_rst = SYNTHETIC_ADC_SOURCE ? ctrl_rst : adc_rst;
    assign sdr_clear_counts = SYNTHETIC_ADC_SOURCE ? clear_status_counts_ctrl : clear_counts_adc;
    assign sdr_core_enable = SYNTHETIC_ADC_SOURCE ? core_enable_ctrl : core_enable_adc;
    assign sdr_adc_offset_binary = SYNTHETIC_ADC_SOURCE ? adc_offset_binary_ctrl : adc_offset_binary_adc;
    assign sdr_ddc0_enable = SYNTHETIC_ADC_SOURCE ? ddc0_enable_ctrl : ddc0_enable_adc;
    assign sdr_ddc0_adc_channel = SYNTHETIC_ADC_SOURCE ? ddc0_adc_channel_ctrl : ddc0_adc_channel_adc;
    assign sdr_ddc0_freq_word = SYNTHETIC_ADC_SOURCE ? ddc0_freq_word_ctrl : ddc0_freq_word_adc;
    assign sdr_ddc0_decim_rate = SYNTHETIC_ADC_SOURCE ? ddc0_decim_rate_ctrl : ddc0_decim_rate_adc;
    assign sdr_ddc0_gain_shift = SYNTHETIC_ADC_SOURCE ? ddc0_gain_shift_ctrl : ddc0_gain_shift_adc;
    assign sdr_ddc0_frequency_hz = SYNTHETIC_ADC_SOURCE ? ddc0_frequency_hz_ctrl : ddc0_frequency_hz_adc;
    assign sdr_ddc0_iq_sample_rate_hz = SYNTHETIC_ADC_SOURCE ? ddc0_iq_sample_rate_hz_ctrl : ddc0_iq_sample_rate_hz_adc;
    assign sdr_ddc0_bandwidth_hz = SYNTHETIC_ADC_SOURCE ? ddc0_bandwidth_hz_ctrl : ddc0_bandwidth_hz_adc;
    assign sdr_ddc0_gain_db_q8 = SYNTHETIC_ADC_SOURCE ? ddc0_gain_db_q8_ctrl : ddc0_gain_db_q8_adc;
    assign sdr_ddc0_config_changed = SYNTHETIC_ADC_SOURCE ? ddc0_config_changed_ctrl : cfg_update_adc;
    assign sdr_adc_ch0_sample_14 = SYNTHETIC_ADC_SOURCE ? synthetic_sample : adc_ch0_sample_14;
    assign sdr_adc_ch1_sample_14 = SYNTHETIC_ADC_SOURCE ? ~synthetic_sample : adc_ch1_sample_14;
    assign sdr_adc_sample_valid = SYNTHETIC_ADC_SOURCE ? sdr_core_enable : dvalid;
    assign adc_debug_flags = {
        19'd0,
        sdr_adc_sample_valid,
        sdr_ddc0_enable,
        sdr_core_enable,
        SYNTHETIC_ADC_SOURCE,
        M_AXIS_TREADY,
        iq_adc_tready,
        iq_adc_tvalid,
        dvalid,
        ddc0_enable_adc,
        core_enable_adc,
        cfg_update_adc,
        clear_counts_adc,
        adc_rst
    };

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
        .adc_timestamp(adc_timestamp),
        .adc_debug_flags(adc_debug_flags),
        .adc_dvalid_count(adc_dvalid_count),
        .adc_cfg_update_count(adc_cfg_update_count),
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

    always @(posedge M_AXIS_FIFO_CLK) begin
        if (adc_rst) begin
            adc_dvalid_count     <= 32'd0;
            adc_cfg_update_count <= 32'd0;
        end else begin
            if (clear_counts_adc) begin
                adc_dvalid_count     <= 32'd0;
                adc_cfg_update_count <= 32'd0;
            end else begin
                if (dvalid) begin
                    adc_dvalid_count <= adc_dvalid_count + 32'd1;
                end
                if (cfg_update_adc) begin
                    adc_cfg_update_count <= adc_cfg_update_count + 32'd1;
                end
            end
        end
    end

    always @(posedge M_AXIS_ACLK) begin
        if (!M_AXIS_ARESETN) begin
            synthetic_sample <= 14'd0;
        end else if (sdr_clear_counts || !sdr_core_enable) begin
            synthetic_sample <= 14'd0;
        end else begin
            synthetic_sample <= synthetic_sample + 14'd1;
        end
    end

    sdr_pl_core u_sdr_pl_core (
        .clk(sdr_clk),
        .rst(sdr_rst),
        .core_enable(sdr_core_enable),
        .clear_status_counts(sdr_clear_counts),
        .adc_offset_binary(sdr_adc_offset_binary),
        .adc_ch0_sample_14(sdr_adc_ch0_sample_14),
        .adc_ch1_sample_14(sdr_adc_ch1_sample_14),
        .adc_sample_valid(sdr_adc_sample_valid),
        .adc_or(1'b0),
        .adc_locked(1'b1),
        .ddc0_enable(sdr_ddc0_enable),
        .ddc0_adc_channel(sdr_ddc0_adc_channel),
        .ddc0_config_changed(sdr_ddc0_config_changed),
        .ddc0_freq_word(sdr_ddc0_freq_word),
        .ddc0_decim_rate(sdr_ddc0_decim_rate),
        .ddc0_gain_shift(sdr_ddc0_gain_shift),
        .ddc0_frequency_hz(sdr_ddc0_frequency_hz),
        .ddc0_iq_sample_rate_hz(sdr_ddc0_iq_sample_rate_hz),
        .ddc0_bandwidth_hz(sdr_ddc0_bandwidth_hz),
        .ddc0_gain_db_q8(sdr_ddc0_gain_db_q8),
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
        .s_clk(sdr_clk),
        .s_rst(sdr_rst),
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
