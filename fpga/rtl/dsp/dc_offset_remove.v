`timescale 1ns/1ps

module dc_offset_remove #(
    parameter WIDTH = 16,
    parameter AVG_SHIFT = 12,
    parameter ACC_WIDTH = WIDTH + AVG_SHIFT + 4
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         enable,
    input  wire signed [WIDTH-1:0]      sample_in,
    input  wire                         sample_valid_in,
    output reg  signed [WIDTH-1:0]      sample_out,
    output reg                          sample_valid_out
);
    reg signed [ACC_WIDTH-1:0] avg_q;
    wire signed [ACC_WIDTH-1:0] sample_q;
    wire signed [ACC_WIDTH-1:0] avg_error;
    wire signed [ACC_WIDTH-1:0] avg_sample;
    wire signed [WIDTH:0]       corrected;

    assign sample_q   = {{(ACC_WIDTH-WIDTH){sample_in[WIDTH-1]}}, sample_in} <<< AVG_SHIFT;
    assign avg_error  = sample_q - avg_q;
    assign avg_sample = avg_q >>> AVG_SHIFT;
    assign corrected  = {sample_in[WIDTH-1], sample_in} - avg_sample[WIDTH:0];

    always @(posedge clk) begin
        if (rst) begin
            avg_q            <= {ACC_WIDTH{1'b0}};
            sample_out       <= {WIDTH{1'b0}};
            sample_valid_out <= 1'b0;
        end else begin
            sample_valid_out <= sample_valid_in;

            if (sample_valid_in) begin
                if (enable) begin
                    avg_q      <= avg_q + (avg_error >>> AVG_SHIFT);
                    sample_out <= corrected[WIDTH-1:0];
                end else begin
                    sample_out <= sample_in;
                end
            end
        end
    end
endmodule
