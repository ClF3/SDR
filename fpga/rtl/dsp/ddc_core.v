`timescale 1ns/1ps

module ddc_core #(
    parameter SAMPLE_WIDTH = 16,
    parameter PHASE_WIDTH = 32,
    parameter TRIG_WIDTH = 16,
    parameter MIX_WIDTH = 32,
    parameter CIC_WIDTH = 56,
    parameter CORDIC_STAGES = 16,
    parameter USE_FIR = 0
) (
    input  wire                           clk,
    input  wire                           rst,
    input  wire                           enable,
    input  wire signed [SAMPLE_WIDTH-1:0] sample_in,
    input  wire                           sample_valid,
    input  wire [PHASE_WIDTH-1:0]         freq_word,
    input  wire [15:0]                    decim_rate,
    input  wire [5:0]                     gain_shift,

    output reg  [31:0]                    m_axis_tdata,
    output reg                            m_axis_tvalid,
    input  wire                           m_axis_tready,
    output reg  [31:0]                    overflow_count,
    output reg  [31:0]                    sample_count,
    output wire                           iq_clip
);
    reg signed [SAMPLE_WIDTH-1:0] sample_delay [0:CORDIC_STAGES-1];
    wire trig_valid;
    wire signed [TRIG_WIDTH-1:0] nco_cos;
    wire signed [TRIG_WIDTH-1:0] nco_sin;
    wire signed [MIX_WIDTH-1:0] mix_i;
    wire signed [MIX_WIDTH-1:0] mix_q;
    wire mix_valid;
    wire signed [CIC_WIDTH-1:0] cic_i;
    wire signed [CIC_WIDTH-1:0] cic_q;
    wire cic_i_valid;
    wire cic_q_valid;
    wire signed [CIC_WIDTH-1:0] fir_i;
    wire signed [CIC_WIDTH-1:0] fir_q;
    wire fir_i_valid;
    wire fir_q_valid;
    wire signed [15:0] i_sc16;
    wire signed [15:0] q_sc16;
    wire sat_valid;
    wire sat_clip;
    wire load_output;
    integer i;

    assign load_output = !m_axis_tvalid || m_axis_tready;
    assign iq_clip = sat_clip;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < CORDIC_STAGES; i = i + 1) begin
                sample_delay[i] <= {SAMPLE_WIDTH{1'b0}};
            end
        end else begin
            sample_delay[0] <= sample_in;
            for (i = 1; i < CORDIC_STAGES; i = i + 1) begin
                sample_delay[i] <= sample_delay[i-1];
            end
        end
    end

    nco #(
        .PHASE_WIDTH(PHASE_WIDTH),
        .AMP_WIDTH(TRIG_WIDTH),
        .CORDIC_STAGES(CORDIC_STAGES)
    ) u_nco (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .sample_valid(sample_valid),
        .freq_word(freq_word),
        .trig_valid(trig_valid),
        .cos_out(nco_cos),
        .sin_out(nco_sin)
    );

    mixer_real_to_iq #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .TRIG_WIDTH(TRIG_WIDTH),
        .OUT_WIDTH(MIX_WIDTH)
    ) u_mixer (
        .clk(clk),
        .rst(rst),
        .sample_in(sample_delay[CORDIC_STAGES-1]),
        .cos_in(nco_cos),
        .sin_in(nco_sin),
        .valid_in(trig_valid),
        .i_out(mix_i),
        .q_out(mix_q),
        .valid_out(mix_valid)
    );

    cic_decimator #(
        .IN_WIDTH(MIX_WIDTH),
        .ACC_WIDTH(CIC_WIDTH),
        .STAGES(3)
    ) u_cic_i (
        .clk(clk),
        .rst(rst),
        .sample_in(mix_i),
        .valid_in(mix_valid),
        .decim_rate(decim_rate),
        .sample_out(cic_i),
        .valid_out(cic_i_valid)
    );

    cic_decimator #(
        .IN_WIDTH(MIX_WIDTH),
        .ACC_WIDTH(CIC_WIDTH),
        .STAGES(3)
    ) u_cic_q (
        .clk(clk),
        .rst(rst),
        .sample_in(mix_q),
        .valid_in(mix_valid),
        .decim_rate(decim_rate),
        .sample_out(cic_q),
        .valid_out(cic_q_valid)
    );

    generate
        if (USE_FIR != 0) begin : g_with_fir
            cic_comp_fir #(.DATA_WIDTH(CIC_WIDTH)) u_fir_i (
                .clk(clk),
                .rst(rst),
                .sample_in(cic_i),
                .valid_in(cic_i_valid),
                .sample_out(fir_i),
                .valid_out(fir_i_valid)
            );

            cic_comp_fir #(.DATA_WIDTH(CIC_WIDTH)) u_fir_q (
                .clk(clk),
                .rst(rst),
                .sample_in(cic_q),
                .valid_in(cic_q_valid),
                .sample_out(fir_q),
                .valid_out(fir_q_valid)
            );
        end else begin : g_bypass_fir
            assign fir_i = cic_i;
            assign fir_q = cic_q;
            assign fir_i_valid = cic_i_valid;
            assign fir_q_valid = cic_q_valid;
        end
    endgenerate

    iq_gain_sat #(
        .DATA_WIDTH(CIC_WIDTH),
        .OUT_WIDTH(16)
    ) u_iq_gain_sat (
        .clk(clk),
        .rst(rst),
        .i_in(fir_i),
        .q_in(fir_q),
        .valid_in(fir_i_valid && fir_q_valid),
        .gain_shift(gain_shift),
        .i_out(i_sc16),
        .q_out(q_sc16),
        .valid_out(sat_valid),
        .clipped(sat_clip)
    );

    always @(posedge clk) begin
        if (rst) begin
            m_axis_tdata   <= 32'd0;
            m_axis_tvalid  <= 1'b0;
            overflow_count <= 32'd0;
            sample_count   <= 32'd0;
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end

            if (sat_valid) begin
                if (load_output) begin
                    // AXI byte lane 0 is tdata[7:0]. Pack I in the low half so
                    // DMA/network payload bytes are int16_le I followed by Q.
                    m_axis_tdata  <= {q_sc16, i_sc16};
                    m_axis_tvalid <= 1'b1;
                    sample_count  <= sample_count + 32'd1;
                end else begin
                    overflow_count <= overflow_count + 32'd1;
                end
            end
        end
    end
endmodule
