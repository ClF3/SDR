`timescale 1ns/1ps

module cic_decimator #(
    parameter IN_WIDTH = 32,
    parameter ACC_WIDTH = 56,
    parameter STAGES = 3
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire signed [IN_WIDTH-1:0]   sample_in,
    input  wire                         valid_in,
    input  wire [15:0]                  decim_rate,
    output reg  signed [ACC_WIDTH-1:0]  sample_out,
    output reg                          valid_out
);
    reg signed [ACC_WIDTH-1:0] integrator [0:STAGES-1];
    reg signed [ACC_WIDTH-1:0] comb_delay [0:STAGES-1];
    reg [15:0] decim_count;
    reg signed [ACC_WIDTH-1:0] comb_value;
    reg signed [ACC_WIDTH-1:0] comb_next;
    wire [15:0] decim_safe;
    wire decim_fire;
    integer i;

    assign decim_safe = (decim_rate == 16'd0) ? 16'd1 : decim_rate;
    assign decim_fire = valid_in && (decim_count == decim_safe - 16'd1);

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < STAGES; i = i + 1) begin
                integrator[i] <= {ACC_WIDTH{1'b0}};
                comb_delay[i] <= {ACC_WIDTH{1'b0}};
            end
            decim_count <= 16'd0;
            sample_out  <= {ACC_WIDTH{1'b0}};
            valid_out   <= 1'b0;
            comb_value  <= {ACC_WIDTH{1'b0}};
            comb_next   <= {ACC_WIDTH{1'b0}};
        end else begin
            valid_out <= 1'b0;

            if (valid_in) begin
                integrator[0] <= integrator[0] + {{(ACC_WIDTH-IN_WIDTH){sample_in[IN_WIDTH-1]}}, sample_in};
                for (i = 1; i < STAGES; i = i + 1) begin
                    integrator[i] <= integrator[i] + integrator[i-1];
                end

                if (decim_fire) begin
                    decim_count <= 16'd0;
                    comb_value = integrator[STAGES-1];
                    for (i = 0; i < STAGES; i = i + 1) begin
                        comb_next      = comb_value - comb_delay[i];
                        comb_delay[i] <= comb_value;
                        comb_value     = comb_next;
                    end
                    sample_out <= comb_value;
                    valid_out  <= 1'b1;
                end else begin
                    decim_count <= decim_count + 16'd1;
                end
            end
        end
    end
endmodule
