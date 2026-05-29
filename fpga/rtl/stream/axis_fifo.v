`timescale 1ns/1ps

module axis_fifo #(
    parameter WIDTH = 32,
    parameter DEPTH_LOG2 = 4
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
    localparam DEPTH = (1 << DEPTH_LOG2);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [DEPTH_LOG2:0] wr_ptr;
    reg [DEPTH_LOG2:0] rd_ptr;

    wire full;
    wire empty;

    assign full  = (wr_ptr[DEPTH_LOG2] != rd_ptr[DEPTH_LOG2]) &&
                   (wr_ptr[DEPTH_LOG2-1:0] == rd_ptr[DEPTH_LOG2-1:0]);
    assign empty = (wr_ptr == rd_ptr);

    assign s_tready = !full;
    assign m_tvalid = !empty;
    assign m_tdata  = mem[rd_ptr[DEPTH_LOG2-1:0]];

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= {(DEPTH_LOG2+1){1'b0}};
            rd_ptr <= {(DEPTH_LOG2+1){1'b0}};
        end else begin
            if (s_tvalid && s_tready) begin
                mem[wr_ptr[DEPTH_LOG2-1:0]] <= s_tdata;
                wr_ptr <= wr_ptr + {{DEPTH_LOG2{1'b0}}, 1'b1};
            end

            if (m_tvalid && m_tready) begin
                rd_ptr <= rd_ptr + {{DEPTH_LOG2{1'b0}}, 1'b1};
            end
        end
    end
endmodule
