`timescale 1ns/1ps

module adc_bitslip_align #(
    parameter DATA_WIDTH = 14,
    parameter LOCK_COUNT = 1024
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire [DATA_WIDTH-1:0] sample_in,
    input  wire                  sample_valid_in,
    output reg  [DATA_WIDTH-1:0] sample_out,
    output reg                   sample_valid_out,
    output reg                   locked
);
    reg [15:0] lock_counter;

    always @(posedge clk) begin
        if (rst) begin
            sample_out       <= {DATA_WIDTH{1'b0}};
            sample_valid_out <= 1'b0;
            locked           <= 1'b0;
            lock_counter     <= 16'd0;
        end else begin
            sample_out       <= sample_in;
            sample_valid_out <= sample_valid_in;

            if (sample_valid_in && !locked) begin
                if (lock_counter == LOCK_COUNT[15:0]) begin
                    locked <= 1'b1;
                end else begin
                    lock_counter <= lock_counter + 16'd1;
                end
            end
        end
    end
endmodule
