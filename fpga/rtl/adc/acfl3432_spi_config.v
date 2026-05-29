`timescale 1ns/1ps

module acfl3432_spi_config (
    input  wire        clk_50m,
    input  wire        rst_n,
    input  wire        conf_en,
    input  wire [31:0] reg_conf,

    output wire        adc_spi_ce,
    output wire        adc_spi_sclk,
    inout  wire        adc_spi_io
);
    wire [24:0] lut_data;
    wire        wr_rd_en;
    wire        valid;
    wire        done;
    wire        mosi_unused;
    wire        rd_done_unused;
    wire        rd_data_unused;

    lut_config u_lut_config (
        .clk(clk_50m),
        .rst_n(rst_n),
        .lut_index(done),
        .reg_conf(reg_conf),
        .conf_en(conf_en),
        .wr_rd_en(wr_rd_en),
        .valid(valid),
        .lut_data(lut_data)
    );

    spi_ctrl #(
        .CPOL(1'b0),
        .CPHA(1'b0),
        .BITS_ORDER(1'b0),
        .ADDR_BIT(15),
        .DATA_BIT(7)
    ) u_spi_ctrl (
        .clk(clk_50m),
        .rst_n(rst_n),
        .addr(lut_data[23:8]),
        .data(lut_data[7:0]),
        .GO(1'b1),
        .SPI_CS(adc_spi_ce),
        .SPI_SCLK(adc_spi_sclk),
        .SPI_IO(adc_spi_io),
        .MOSI(mosi_unused),
        .DIV_PARAM(1'b0),
        .cmd_valid(valid),
        .wr_rd_en(wr_rd_en),
        .done(done),
        .rd_done(rd_done_unused),
        .rd_data(rd_data_unused)
    );
endmodule
