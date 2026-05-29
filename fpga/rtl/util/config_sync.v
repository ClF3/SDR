`timescale 1ns/1ps

module config_sync #(
    parameter WIDTH = 32
) (
    input  wire             src_clk,
    input  wire             src_rst,
    input  wire [WIDTH-1:0] src_data,
    input  wire             src_update,

    input  wire             dst_clk,
    input  wire             dst_rst,
    output reg  [WIDTH-1:0] dst_data,
    output wire             dst_update
);
    reg [WIDTH-1:0] src_hold;
    reg             src_toggle;
    reg             dst_meta;
    reg             dst_sync;
    reg             dst_sync_d;

    always @(posedge src_clk) begin
        if (src_rst) begin
            src_hold   <= {WIDTH{1'b0}};
            src_toggle <= 1'b0;
        end else if (src_update) begin
            src_hold   <= src_data;
            src_toggle <= ~src_toggle;
        end
    end

    always @(posedge dst_clk) begin
        if (dst_rst) begin
            dst_meta   <= 1'b0;
            dst_sync   <= 1'b0;
            dst_sync_d <= 1'b0;
            dst_data   <= {WIDTH{1'b0}};
        end else begin
            dst_meta   <= src_toggle;
            dst_sync   <= dst_meta;
            dst_sync_d <= dst_sync;
            if (dst_sync ^ dst_sync_d) begin
                dst_data <= src_hold;
            end
        end
    end

    assign dst_update = dst_sync ^ dst_sync_d;
endmodule
