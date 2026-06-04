`timescale 1ns/1ps

module axi_lite_slave (
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    output wire        core_enable,
    output wire        soft_reset_pulse,
    output wire        adc_offset_binary,
    output wire        clear_status_counts,
    output wire        ddc0_enable,
    output wire        ddc0_adc_channel,
    output wire [31:0] ddc0_freq_word,
    output wire [15:0] ddc0_decim_rate,
    output wire [5:0]  ddc0_gain_shift,
    output wire [63:0] ddc0_frequency_hz,
    output wire [31:0] ddc0_iq_sample_rate_hz,
    output wire [31:0] ddc0_bandwidth_hz,
    output wire signed [15:0] ddc0_gain_db_q8,
    output wire        ddc0_config_changed,

    input  wire        adc_locked,
    input  wire        adc_or,
    input  wire [15:0] adc_peak_abs,
    input  wire [31:0] adc_rms_power,
    input  wire [31:0] adc_or_count,
    input  wire [31:0] adc_clip_count,
    input  wire [63:0] adc_timestamp,
    input  wire [31:0] adc_debug_flags,
    input  wire [31:0] adc_dvalid_count,
    input  wire [31:0] adc_cfg_update_count,
    input  wire [31:0] ddc0_sample_count,
    input  wire [31:0] ddc0_overflow_count
);
    reg        aw_hold;
    reg        w_hold;
    reg [11:0] awaddr_hold;
    reg [31:0] wdata_hold;
    reg [3:0]  wstrb_hold;
    reg [11:0] rd_addr;
    wire [31:0] csr_rd_data;
    wire wr_fire;

    assign s_axi_awready = !aw_hold && !s_axi_bvalid;
    assign s_axi_wready  = !w_hold && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;
    assign wr_fire = aw_hold && w_hold && !s_axi_bvalid;

    always @(posedge clk) begin
        if (rst) begin
            aw_hold       <= 1'b0;
            w_hold        <= 1'b0;
            awaddr_hold   <= 12'd0;
            wdata_hold    <= 32'd0;
            wstrb_hold    <= 4'd0;
            s_axi_bresp   <= 2'b00;
            s_axi_bvalid  <= 1'b0;
            rd_addr       <= 12'd0;
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= 2'b00;
            s_axi_rvalid  <= 1'b0;
        end else begin
            if (s_axi_awready && s_axi_awvalid) begin
                aw_hold     <= 1'b1;
                awaddr_hold <= s_axi_awaddr[11:0];
            end

            if (s_axi_wready && s_axi_wvalid) begin
                w_hold     <= 1'b1;
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
            end

            if (wr_fire) begin
                aw_hold      <= 1'b0;
                w_hold       <= 1'b0;
                s_axi_bresp  <= 2'b00;
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (s_axi_arready && s_axi_arvalid) begin
                rd_addr      <= s_axi_araddr[11:0];
                s_axi_rdata  <= csr_rd_data;
                s_axi_rresp  <= 2'b00;
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    csr_regfile u_csr_regfile (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_fire),
        .wr_addr(awaddr_hold),
        .wr_data(wdata_hold),
        .wr_strb(wstrb_hold),
        .rd_addr(s_axi_araddr[11:0]),
        .rd_data(csr_rd_data),
        .core_enable(core_enable),
        .soft_reset_pulse(soft_reset_pulse),
        .adc_offset_binary(adc_offset_binary),
        .clear_status_counts(clear_status_counts),
        .ddc0_enable(ddc0_enable),
        .ddc0_adc_channel(ddc0_adc_channel),
        .ddc0_freq_word(ddc0_freq_word),
        .ddc0_decim_rate(ddc0_decim_rate),
        .ddc0_gain_shift(ddc0_gain_shift),
        .ddc0_frequency_hz(ddc0_frequency_hz),
        .ddc0_iq_sample_rate_hz(ddc0_iq_sample_rate_hz),
        .ddc0_bandwidth_hz(ddc0_bandwidth_hz),
        .ddc0_gain_db_q8(ddc0_gain_db_q8),
        .ddc0_config_changed(ddc0_config_changed),
        .adc_locked(adc_locked),
        .adc_or(adc_or),
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
endmodule
