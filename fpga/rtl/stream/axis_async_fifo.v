`timescale 1ns/1ps

module axis_async_fifo #(
    parameter WIDTH = 32,
    parameter ADDR_WIDTH = 10
) (
    input  wire             s_clk,
    input  wire             s_rst,
    input  wire [WIDTH-1:0] s_tdata,
    input  wire             s_tvalid,
    output wire             s_tready,

    input  wire             m_clk,
    input  wire             m_rst,
    output wire [WIDTH-1:0] m_tdata,
    output wire             m_tvalid,
    input  wire             m_tready
);
    localparam DEPTH = (1 << ADDR_WIDTH);

    reg [WIDTH-1:0] mem [0:DEPTH-1];

    reg [ADDR_WIDTH:0] s_bin;
    reg [ADDR_WIDTH:0] s_gray;
    reg [ADDR_WIDTH:0] s_gray_m1;
    reg [ADDR_WIDTH:0] s_gray_m2;

    reg [ADDR_WIDTH:0] m_bin;
    reg [ADDR_WIDTH:0] m_gray;
    reg [ADDR_WIDTH:0] m_gray_s1;
    reg [ADDR_WIDTH:0] m_gray_s2;
    reg                s_full;
    reg                m_empty;

    wire               s_push;
    wire               m_pop;
    wire [ADDR_WIDTH:0] s_bin_next;
    wire [ADDR_WIDTH:0] s_gray_next;
    wire [ADDR_WIDTH:0] m_bin_next;
    wire [ADDR_WIDTH:0] m_gray_next;
    wire               full_next;
    wire               empty_next;

    assign s_push = s_tvalid && !s_full;
    assign m_pop  = m_tready && !m_empty;

    assign s_bin_next  = s_bin + {{ADDR_WIDTH{1'b0}}, s_push};
    assign s_gray_next = (s_bin_next >> 1) ^ s_bin_next;
    assign m_bin_next  = m_bin + {{ADDR_WIDTH{1'b0}}, m_pop};
    assign m_gray_next = (m_bin_next >> 1) ^ m_bin_next;

    assign full_next = (s_gray_next == {
        ~s_gray_m2[ADDR_WIDTH:ADDR_WIDTH-1],
        s_gray_m2[ADDR_WIDTH-2:0]
    });
    assign empty_next = (m_gray_next == m_gray_s2);

    assign s_tready = !s_full;
    assign m_tvalid = !m_empty;
    assign m_tdata  = mem[m_bin[ADDR_WIDTH-1:0]];

    always @(posedge s_clk) begin
        if (s_rst) begin
            s_bin     <= {(ADDR_WIDTH+1){1'b0}};
            s_gray    <= {(ADDR_WIDTH+1){1'b0}};
            s_gray_m1 <= {(ADDR_WIDTH+1){1'b0}};
            s_gray_m2 <= {(ADDR_WIDTH+1){1'b0}};
            s_full    <= 1'b0;
        end else begin
            s_gray_m1 <= m_gray;
            s_gray_m2 <= s_gray_m1;
            if (s_push) begin
                mem[s_bin[ADDR_WIDTH-1:0]] <= s_tdata;
            end
            s_bin  <= s_bin_next;
            s_gray <= s_gray_next;
            s_full <= full_next;
        end
    end

    always @(posedge m_clk) begin
        if (m_rst) begin
            m_bin     <= {(ADDR_WIDTH+1){1'b0}};
            m_gray    <= {(ADDR_WIDTH+1){1'b0}};
            m_gray_s1 <= {(ADDR_WIDTH+1){1'b0}};
            m_gray_s2 <= {(ADDR_WIDTH+1){1'b0}};
            m_empty   <= 1'b1;
        end else begin
            m_gray_s1 <= s_gray;
            m_gray_s2 <= m_gray_s1;
            m_bin     <= m_bin_next;
            m_gray    <= m_gray_next;
            m_empty   <= empty_next;
        end
    end
endmodule
