`timescale 1ns/1ps

module axis_rate_adapter #(
    parameter WIDTH = 32
) (
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] s_tdata,
    input  wire             s_tvalid,
    output wire             s_tready,
    output wire [WIDTH-1:0] m_tdata,
    output wire             m_tvalid,
    input  wire             m_tready
);
    skid_buffer #(.WIDTH(WIDTH)) u_skid_buffer (
        .clk(clk),
        .rst(rst),
        .s_data(s_tdata),
        .s_valid(s_tvalid),
        .s_ready(s_tready),
        .m_data(m_tdata),
        .m_valid(m_tvalid),
        .m_ready(m_tready)
    );
endmodule
