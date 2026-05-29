`timescale 1ns/1ps

module pulse_sync (
    input  wire src_clk,
    input  wire src_rst,
    input  wire src_pulse,
    input  wire dst_clk,
    input  wire dst_rst,
    output wire dst_pulse
);
    reg src_toggle;
    reg dst_meta;
    reg dst_sync;
    reg dst_sync_d;

    always @(posedge src_clk) begin
        if (src_rst) begin
            src_toggle <= 1'b0;
        end else if (src_pulse) begin
            src_toggle <= ~src_toggle;
        end
    end

    always @(posedge dst_clk) begin
        if (dst_rst) begin
            dst_meta   <= 1'b0;
            dst_sync   <= 1'b0;
            dst_sync_d <= 1'b0;
        end else begin
            dst_meta   <= src_toggle;
            dst_sync   <= dst_meta;
            dst_sync_d <= dst_sync;
        end
    end

    assign dst_pulse = dst_sync ^ dst_sync_d;
endmodule
