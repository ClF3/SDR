`timescale 1ns/1ps

module acfl3432_adc_frontend (
    input  wire        adc_ref_clk,
    input  wire        adc_reset,

    input  wire        adc1_clk_p,
    input  wire        adc1_clk_n,
    input  wire [13:0] adc1_data_p,
    input  wire [13:0] adc1_data_n,

    output wire        adc_clk_p,
    output wire        adc_clk_n,

    output wire        adc_sample_clk,
    output reg  [13:0] adc_ch0_sample_14,
    output reg  [13:0] adc_ch1_sample_14,
    output reg         adc_sample_valid
);
`ifdef USE_XILINX_PRIMS
    wire [13:0] adc_data_se;
    wire [13:0] adc_data_a;
    wire [13:0] adc_data_b;

    OBUFDS u_adc_clk_obufds (
        .O(adc_clk_p),
        .OB(adc_clk_n),
        .I(adc_ref_clk)
    );

    IBUFDS u_adc_dco_ibufds (
        .O(adc_sample_clk),
        .I(adc1_clk_p),
        .IB(adc1_clk_n)
    );

    genvar i;
    generate
        for (i = 0; i < 14; i = i + 1) begin : g_adc_data
            IBUFDS u_adc_data_ibufds (
                .O(adc_data_se[i]),
                .I(adc1_data_p[i]),
                .IB(adc1_data_n[i])
            );

            IDDRE1 #(
                .DDR_CLK_EDGE("OPPOSITE_EDGE"),
                .IS_CB_INVERTED(1'b1),
                .IS_C_INVERTED(1'b0)
            ) u_adc_data_iddr (
                .Q1(adc_data_a[i]),
                .Q2(adc_data_b[i]),
                .C(adc_sample_clk),
                .CB(adc_sample_clk),
                .D(adc_data_se[i]),
                .R(1'b0)
            );
        end
    endgenerate
`else
    wire [13:0] adc_data_a;
    wire [13:0] adc_data_b;

    assign adc_clk_p = adc_ref_clk;
    assign adc_clk_n = ~adc_ref_clk;
    assign adc_sample_clk = adc1_clk_p;
    assign adc_data_a = adc1_data_p;
    assign adc_data_b = adc1_data_n;
`endif

    always @(posedge adc_sample_clk) begin
        if (adc_reset) begin
            adc_ch0_sample_14 <= 14'd0;
            adc_ch1_sample_14 <= 14'd0;
            adc_sample_valid  <= 1'b0;
        end else begin
            adc_ch0_sample_14 <= adc_data_a;
            adc_ch1_sample_14 <= adc_data_b;
            adc_sample_valid  <= 1'b1;
        end
    end
endmodule
