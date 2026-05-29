`timescale 1ns/1ps

module csr_regfile (
    input  wire        clk,
    input  wire        rst,

    input  wire        wr_en,
    input  wire [11:0] wr_addr,
    input  wire [31:0] wr_data,
    input  wire [3:0]  wr_strb,

    input  wire [11:0] rd_addr,
    output reg  [31:0] rd_data,

    output wire        core_enable,
    output reg         soft_reset_pulse,
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
    output reg         ddc0_config_changed,

    input  wire        adc_locked,
    input  wire        adc_or,
    input  wire [15:0] adc_peak_abs,
    input  wire [31:0] adc_rms_power,
    input  wire [31:0] adc_or_count,
    input  wire [31:0] adc_clip_count,
    input  wire [31:0] ddc0_sample_count,
    input  wire [31:0] ddc0_overflow_count
);
    localparam CORE_ID      = 32'h53445231; // "SDR1"
    localparam CORE_VERSION = 32'h0001_0000;

    localparam A_CORE_ID        = 12'h000;
    localparam A_CORE_VERSION   = 12'h004;
    localparam A_CONTROL        = 12'h008;
    localparam A_ADC_STATUS     = 12'h00c;
    localparam A_ADC_PEAK       = 12'h010;
    localparam A_ADC_RMS        = 12'h014;
    localparam A_OR_COUNT       = 12'h018;
    localparam A_CLIP_COUNT     = 12'h01c;
    localparam A_CLEAR_COUNTS   = 12'h020;

    localparam A_DDC0_CONTROL   = 12'h100;
    localparam A_DDC0_FREQ_WORD = 12'h104;
    localparam A_DDC0_DECIM     = 12'h108;
    localparam A_DDC0_GAIN      = 12'h10c;
    localparam A_DDC0_SAMPLES   = 12'h110;
    localparam A_DDC0_OVERFLOW  = 12'h114;
    localparam A_DDC0_FREQ_HZ_L = 12'h118;
    localparam A_DDC0_FREQ_HZ_H = 12'h11c;
    localparam A_DDC0_IQ_RATE   = 12'h120;
    localparam A_DDC0_BANDWIDTH = 12'h124;
    localparam A_DDC0_GAIN_DB   = 12'h128;

    reg [31:0] control_reg;
    reg [31:0] ddc0_control_reg;
    reg [31:0] ddc0_freq_word_reg;
    reg [31:0] ddc0_decim_reg;
    reg [31:0] ddc0_gain_reg;
    reg [63:0] ddc0_frequency_hz_reg;
    reg [31:0] ddc0_iq_rate_reg;
    reg [31:0] ddc0_bandwidth_reg;
    reg [31:0] ddc0_gain_db_reg;
    reg        clear_counts_reg;

    assign core_enable        = control_reg[0];
    assign adc_offset_binary  = control_reg[2];
    assign clear_status_counts = clear_counts_reg;

    assign ddc0_enable      = ddc0_control_reg[0];
    assign ddc0_adc_channel = ddc0_control_reg[1];
    assign ddc0_freq_word   = ddc0_freq_word_reg;
    assign ddc0_decim_rate  = (ddc0_decim_reg[15:0] == 16'd0) ? 16'd1 : ddc0_decim_reg[15:0];
    assign ddc0_gain_shift  = ddc0_gain_reg[5:0];
    assign ddc0_frequency_hz = ddc0_frequency_hz_reg;
    assign ddc0_iq_sample_rate_hz = ddc0_iq_rate_reg;
    assign ddc0_bandwidth_hz = ddc0_bandwidth_reg;
    assign ddc0_gain_db_q8 = ddc0_gain_db_reg[15:0];

    always @(posedge clk) begin
        if (rst) begin
            control_reg        <= 32'd0;
            ddc0_control_reg   <= 32'd0;
            ddc0_freq_word_reg <= 32'd0;
            ddc0_decim_reg     <= 32'd1000;
            ddc0_gain_reg      <= 32'd30;
            ddc0_frequency_hz_reg <= 64'd0;
            ddc0_iq_rate_reg   <= 32'd250000;
            ddc0_bandwidth_reg <= 32'd12000;
            ddc0_gain_db_reg   <= 32'd0;
            soft_reset_pulse   <= 1'b0;
            clear_counts_reg   <= 1'b0;
            ddc0_config_changed <= 1'b0;
        end else begin
            soft_reset_pulse <= 1'b0;
            clear_counts_reg <= 1'b0;
            ddc0_config_changed <= 1'b0;

            if (wr_en) begin
                case (wr_addr)
                    A_CONTROL: begin
                        if (wr_strb[0]) control_reg[7:0]   <= wr_data[7:0];
                        if (wr_strb[1]) control_reg[15:8]  <= wr_data[15:8];
                        if (wr_strb[2]) control_reg[23:16] <= wr_data[23:16];
                        if (wr_strb[3]) control_reg[31:24] <= wr_data[31:24];
                        soft_reset_pulse <= wr_data[1];
                        ddc0_config_changed <= 1'b1;
                    end
                    A_CLEAR_COUNTS: begin
                        clear_counts_reg <= wr_data[0];
                    end
                    A_DDC0_CONTROL: begin
                        if (wr_strb[0]) ddc0_control_reg[7:0]   <= wr_data[7:0];
                        if (wr_strb[1]) ddc0_control_reg[15:8]  <= wr_data[15:8];
                        if (wr_strb[2]) ddc0_control_reg[23:16] <= wr_data[23:16];
                        if (wr_strb[3]) ddc0_control_reg[31:24] <= wr_data[31:24];
                        ddc0_config_changed <= 1'b1;
                    end
                    A_DDC0_FREQ_WORD: begin
                        if (wr_strb[0]) ddc0_freq_word_reg[7:0]   <= wr_data[7:0];
                        if (wr_strb[1]) ddc0_freq_word_reg[15:8]  <= wr_data[15:8];
                        if (wr_strb[2]) ddc0_freq_word_reg[23:16] <= wr_data[23:16];
                        if (wr_strb[3]) ddc0_freq_word_reg[31:24] <= wr_data[31:24];
                        ddc0_config_changed <= 1'b1;
                    end
                    A_DDC0_DECIM: begin
                        if (wr_strb[0]) ddc0_decim_reg[7:0]   <= wr_data[7:0];
                        if (wr_strb[1]) ddc0_decim_reg[15:8]  <= wr_data[15:8];
                        if (wr_strb[2]) ddc0_decim_reg[23:16] <= wr_data[23:16];
                        if (wr_strb[3]) ddc0_decim_reg[31:24] <= wr_data[31:24];
                        ddc0_config_changed <= 1'b1;
                    end
                    A_DDC0_GAIN: begin
                        if (wr_strb[0]) ddc0_gain_reg[7:0]   <= wr_data[7:0];
                        if (wr_strb[1]) ddc0_gain_reg[15:8]  <= wr_data[15:8];
                        if (wr_strb[2]) ddc0_gain_reg[23:16] <= wr_data[23:16];
                        if (wr_strb[3]) ddc0_gain_reg[31:24] <= wr_data[31:24];
                        ddc0_config_changed <= 1'b1;
                    end
                    A_DDC0_FREQ_HZ_L: begin
                        if (wr_strb[0]) ddc0_frequency_hz_reg[7:0]   <= wr_data[7:0];
                        if (wr_strb[1]) ddc0_frequency_hz_reg[15:8]  <= wr_data[15:8];
                        if (wr_strb[2]) ddc0_frequency_hz_reg[23:16] <= wr_data[23:16];
                        if (wr_strb[3]) ddc0_frequency_hz_reg[31:24] <= wr_data[31:24];
                        ddc0_config_changed <= 1'b1;
                    end
                    A_DDC0_FREQ_HZ_H: begin
                        if (wr_strb[0]) ddc0_frequency_hz_reg[39:32] <= wr_data[7:0];
                        if (wr_strb[1]) ddc0_frequency_hz_reg[47:40] <= wr_data[15:8];
                        if (wr_strb[2]) ddc0_frequency_hz_reg[55:48] <= wr_data[23:16];
                        if (wr_strb[3]) ddc0_frequency_hz_reg[63:56] <= wr_data[31:24];
                        ddc0_config_changed <= 1'b1;
                    end
                    A_DDC0_IQ_RATE: begin
                        if (wr_strb[0]) ddc0_iq_rate_reg[7:0]   <= wr_data[7:0];
                        if (wr_strb[1]) ddc0_iq_rate_reg[15:8]  <= wr_data[15:8];
                        if (wr_strb[2]) ddc0_iq_rate_reg[23:16] <= wr_data[23:16];
                        if (wr_strb[3]) ddc0_iq_rate_reg[31:24] <= wr_data[31:24];
                        ddc0_config_changed <= 1'b1;
                    end
                    A_DDC0_BANDWIDTH: begin
                        if (wr_strb[0]) ddc0_bandwidth_reg[7:0]   <= wr_data[7:0];
                        if (wr_strb[1]) ddc0_bandwidth_reg[15:8]  <= wr_data[15:8];
                        if (wr_strb[2]) ddc0_bandwidth_reg[23:16] <= wr_data[23:16];
                        if (wr_strb[3]) ddc0_bandwidth_reg[31:24] <= wr_data[31:24];
                        ddc0_config_changed <= 1'b1;
                    end
                    A_DDC0_GAIN_DB: begin
                        if (wr_strb[0]) ddc0_gain_db_reg[7:0]   <= wr_data[7:0];
                        if (wr_strb[1]) ddc0_gain_db_reg[15:8]  <= wr_data[15:8];
                        if (wr_strb[2]) ddc0_gain_db_reg[23:16] <= wr_data[23:16];
                        if (wr_strb[3]) ddc0_gain_db_reg[31:24] <= wr_data[31:24];
                        ddc0_config_changed <= 1'b1;
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

    always @(*) begin
        case (rd_addr)
            A_CORE_ID:        rd_data = CORE_ID;
            A_CORE_VERSION:   rd_data = CORE_VERSION;
            A_CONTROL:        rd_data = control_reg;
            A_ADC_STATUS:     rd_data = {29'd0, adc_or, adc_locked, core_enable};
            A_ADC_PEAK:       rd_data = {16'd0, adc_peak_abs};
            A_ADC_RMS:        rd_data = adc_rms_power;
            A_OR_COUNT:       rd_data = adc_or_count;
            A_CLIP_COUNT:     rd_data = adc_clip_count;
            A_DDC0_CONTROL:   rd_data = ddc0_control_reg;
            A_DDC0_FREQ_WORD: rd_data = ddc0_freq_word_reg;
            A_DDC0_DECIM:     rd_data = ddc0_decim_reg;
            A_DDC0_GAIN:      rd_data = ddc0_gain_reg;
            A_DDC0_SAMPLES:   rd_data = ddc0_sample_count;
            A_DDC0_OVERFLOW:  rd_data = ddc0_overflow_count;
            A_DDC0_FREQ_HZ_L: rd_data = ddc0_frequency_hz_reg[31:0];
            A_DDC0_FREQ_HZ_H: rd_data = ddc0_frequency_hz_reg[63:32];
            A_DDC0_IQ_RATE:   rd_data = ddc0_iq_rate_reg;
            A_DDC0_BANDWIDTH: rd_data = ddc0_bandwidth_reg;
            A_DDC0_GAIN_DB:   rd_data = ddc0_gain_db_reg;
            default:          rd_data = 32'd0;
        endcase
    end
endmodule
