`timescale 1ns / 1ps

module ACFL3432_ctrl(
    input                     conf_en,
    input [31:0]              reg_conf,
    input                     clk_50,
    input                     clk_100,
    input                     rst,

    output                    adc1_clk,
    output reg [13:0]         adc1_data_a_d0,
    output reg [13:0]         adc1_data_b_d0,

    output                    adc_clk_p,
    output                    adc_clk_n,
    output                    adc1_spi_ce,
    output                    adc1_spi_sclk,
    inout                     adc1_spi_io,
    input                     adc1_clk_p,
    input                     adc1_clk_n,
    input  [13:0]             adc1_data_p,
    input  [13:0]             adc1_data_n
);

    wire [24:0] adc1_lut_data;
    wire        wr_rd_en;
    wire        valid;
    wire        done;
    wire [13:0] adc1_data;
    wire [13:0] adc1_data_a;
    wire [13:0] adc1_data_b;

    OBUFDS OBUFDS_inst (
        .O(adc_clk_p),
        .OB(adc_clk_n),
        .I(clk_100)
    );

    IBUFDS IBUFDS_adc1_clk (
        .O(adc1_clk),
        .I(adc1_clk_p),
        .IB(adc1_clk_n)
    );

    genvar i;
    generate
        for (i = 0; i < 14; i = i + 1) begin : IBUFDS_DATAS
            IBUFDS IBUFDS_adc1_data (
                .O(adc1_data[i]),
                .I(adc1_data_p[i]),
                .IB(adc1_data_n[i])
            );

            IDDRE1 #(
                .DDR_CLK_EDGE("OPPOSITE_EDGE"),
                .IS_CB_INVERTED(1'b1),
                .IS_C_INVERTED(1'b0)
            ) IDDR_adc1_data (
                .Q1(adc1_data_a[i]),
                .Q2(adc1_data_b[i]),
                .C(adc1_clk),
                .CB(adc1_clk),
                .D(adc1_data[i]),
                .R(1'b0)
            );
        end
    endgenerate

    always @(posedge adc1_clk) begin
        adc1_data_a_d0 <= adc1_data_a;
        adc1_data_b_d0 <= adc1_data_b;
    end

    lut_config lut_config_adc1 (
        .clk(clk_50),
        .rst_n(~rst),
        .reg_conf(reg_conf),
        .wr_rd_en(wr_rd_en),
        .conf_en(conf_en),
        .valid(valid),
        .lut_index(done),
        .lut_data(adc1_lut_data)
    );

    wire MOSI;

    spi_ctrl #(
        .CPOL('b0),
        .CPHA('b0),
        .BITS_ORDER('b0),
        .ADDR_BIT('d16 - 'b1),
        .DATA_BIT('d8 - 'b1)
    ) spi_ctrl (
        .clk(clk_50),
        .rst_n(~rst),
        .addr(adc1_lut_data[23:8]),
        .data(adc1_lut_data[7:0]),
        .GO(1),
        .SPI_CS(adc1_spi_ce),
        .SPI_SCLK(adc1_spi_sclk),
        .SPI_IO(adc1_spi_io),
        .MOSI(MOSI),
        .DIV_PARAM(16'd500),
        .cmd_valid(valid),
        .done(done),
        .wr_rd_en(wr_rd_en),
        .rd_done(),
        .rd_data()
    );

endmodule
