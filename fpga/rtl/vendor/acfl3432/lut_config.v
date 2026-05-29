`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////////
// Company       : 武汉芯路恒科技有限公司
//                 http://xiaomeige.taobao.com
// Web           : http://www.corecourse.cn
// 
// Create Date: 2025/09/01 
// Design Name: 
// Module Name: 
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module lut_config(
    input              clk,
    input              rst_n,
    input              lut_index,   // Look-up table address
    input  [31:0]      reg_conf,    // 外部写寄存器数据
    input              conf_en,     // 外部写寄存器使能
    output reg         wr_rd_en,    // 读写使能，1写0读
    output reg         valid,       // 数据有效信号
    output reg [24:0]  lut_data     // reg address reg data
);

    reg conf_en_reg;
    always @(posedge clk or negedge rst_n) begin   
    if (!rst_n)
        conf_en_reg <= 0;
    else 
        conf_en_reg <= conf_en;
    end
reg [9:0] state;

always @(posedge clk or negedge rst_n) begin   
    if (!rst_n)
        state <= 0;
    else if (lut_index)
        state <= state + 1;
    else 
        state <= state;
end

reg [3:0] conf_state;
always @(posedge clk or negedge rst_n) begin   
if (!rst_n) begin
    wr_rd_en <= 1;      // 默认写
    valid    <= 0;
    conf_state <= 0;
    lut_data <= {16'hffff, 8'hff};
end else begin
    case(conf_state)
        0   :   begin conf_state <= conf_state + 1;end
        1   :   begin
                case (state)
////////////////////////////////////////////////////////////////////////////////////ACM9648
//                    10'd0: begin lut_data <= {16'h0014 , 8'hA0};valid <= 1; end
//                    10'd1: begin lut_data <= {16'h0017 , 8'h00};valid <= 1; end
//                    10'd2: begin lut_data <= {16'h000b , 8'h00};valid <= 1; end
//                    10'd3: begin lut_data <= {16'h00ff , 8'h01};valid <= 0; end
//                    10'd4: begin conf_state <= conf_state + 1; valid <= 0; end
////////////////////////////////////////////////////////////////////////////////////ACFL3432
                10'd0: begin lut_data <= {16'h0014 , 8'h05};valid <= 1; end
                10'd1: begin lut_data <= {16'h0017 , 8'h85};valid <= 1; end
                10'd2: begin lut_data <= {16'h000b , 8'h00};valid <= 1; end
                10'd3: begin lut_data <= {16'h0018 , 8'h0F};valid <= 1; end
                10'd4: begin lut_data <= {16'h00ff , 8'h01};valid <= 1; end
                10'd5: begin conf_state <= conf_state + 1; valid <= 0; end
                default: lut_data <= {16'hffff, 8'hff};
                endcase
            end
            
        2   :   if(conf_en_reg)begin
                    lut_data <= reg_conf[23:0];
                    valid <= 1;
                    conf_state <= conf_state + 1;
                 end else begin
                    valid <= 0;
                    conf_state <= conf_state;
                 end
                 
        3   :    if(lut_index)begin
                    lut_data <= {16'h00ff , 8'h01};
                    valid <= 1;
                    conf_state <= conf_state + 1;
                end else
                    conf_state <= conf_state;
                    
        4   :   begin 
                valid <= 0; 
                if(lut_index)begin 
                    
                    conf_state <= 2;
                  end else
                    conf_state <= conf_state;
                end
        default :   conf_state <= 0;
    endcase 
  end
end

endmodule
