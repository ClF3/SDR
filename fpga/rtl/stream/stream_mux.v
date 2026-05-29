`timescale 1ns/1ps

module stream_mux (
    input  wire        select_b,
    input  wire [31:0] a_tdata,
    input  wire        a_tvalid,
    output wire        a_tready,
    input  wire [31:0] b_tdata,
    input  wire        b_tvalid,
    output wire        b_tready,
    output wire [31:0] m_tdata,
    output wire        m_tvalid,
    input  wire        m_tready
);
    assign m_tdata  = select_b ? b_tdata : a_tdata;
    assign m_tvalid = select_b ? b_tvalid : a_tvalid;
    assign a_tready = !select_b && m_tready;
    assign b_tready = select_b && m_tready;
endmodule
