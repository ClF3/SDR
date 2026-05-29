`timescale 1ns/1ps

module skid_buffer #(
    parameter WIDTH = 32
) (
    input  wire             clk,
    input  wire             rst,

    input  wire [WIDTH-1:0] s_data,
    input  wire             s_valid,
    output wire             s_ready,

    output wire [WIDTH-1:0] m_data,
    output wire             m_valid,
    input  wire             m_ready
);
    reg [WIDTH-1:0] data_reg;
    reg             valid_reg;

    assign s_ready = !valid_reg || m_ready;
    assign m_data  = data_reg;
    assign m_valid = valid_reg;

    always @(posedge clk) begin
        if (rst) begin
            data_reg  <= {WIDTH{1'b0}};
            valid_reg <= 1'b0;
        end else begin
            if (s_ready) begin
                data_reg  <= s_data;
                valid_reg <= s_valid;
            end
        end
    end
endmodule
