`timescale 1ns/1ps

module adc_level_monitor #(
    parameter WIDTH = 16,
    parameter WINDOW_LOG2 = 16,
    parameter CLIP_LEVEL = 16'sh7f00
) (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    clear_counts,
    input  wire signed [WIDTH-1:0] sample_in,
    input  wire                    sample_valid,
    input  wire                    adc_or,
    input  wire                    extra_clip,

    output reg  [WIDTH-1:0]        peak_abs,
    output reg  [31:0]             rms_power,
    output reg  [31:0]             or_count,
    output reg  [31:0]             clip_count
);
    reg [WINDOW_LOG2-1:0] window_count;
    reg [WIDTH-1:0]       peak_work;
    reg [63:0]            power_acc;
    reg                   adc_or_d;

    wire [WIDTH-1:0] abs_sample;
    wire [WIDTH-1:0] peak_next;
    wire [31:0]      power_sample;
    wire [63:0]      power_next;
    wire             window_last;
    wire             clip_hit;
    wire             or_rise;

    assign abs_sample   = sample_in[WIDTH-1] ? (~sample_in + {{(WIDTH-1){1'b0}}, 1'b1}) : sample_in;
    assign peak_next    = (abs_sample > peak_work) ? abs_sample : peak_work;
    assign power_sample = abs_sample * abs_sample;
    assign power_next   = power_acc + power_sample;
    assign window_last  = sample_valid && (&window_count);
    assign clip_hit     = sample_valid && (abs_sample >= CLIP_LEVEL[WIDTH-1:0]);
    assign or_rise      = adc_or && !adc_or_d;

    always @(posedge clk) begin
        if (rst) begin
            window_count <= {WINDOW_LOG2{1'b0}};
            peak_work    <= {WIDTH{1'b0}};
            power_acc    <= 64'd0;
            peak_abs     <= {WIDTH{1'b0}};
            rms_power    <= 32'd0;
            or_count     <= 32'd0;
            clip_count   <= 32'd0;
            adc_or_d     <= 1'b0;
        end else begin
            adc_or_d <= adc_or;

            if (clear_counts) begin
                or_count   <= 32'd0;
                clip_count <= 32'd0;
            end else begin
                if (or_rise) begin
                    or_count <= or_count + 32'd1;
                end

                if (clip_hit || extra_clip) begin
                    clip_count <= clip_count + 32'd1;
                end
            end

            if (sample_valid) begin
                if (window_last) begin
                    peak_abs     <= peak_next;
                    rms_power    <= power_next >> WINDOW_LOG2;
                    window_count <= {WINDOW_LOG2{1'b0}};
                    peak_work    <= {WIDTH{1'b0}};
                    power_acc    <= 64'd0;
                end else begin
                    window_count <= window_count + {{(WINDOW_LOG2-1){1'b0}}, 1'b1};
                    peak_work    <= peak_next;
                    power_acc    <= power_next;
                end
            end
        end
    end
endmodule
