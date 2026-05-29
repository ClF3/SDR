`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////////
// Company       : 武汉芯路恒科技有限公司
//                 http://xiaomeige.taobao.com
// Web           : http://www.corecourse.cn
// 
// Create Date: 2025/09/01 09:21:29
// Design Name: 
// Module Name: spi_ctrl
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

//控制模块，可以通过外部输入数据控制读写状态     
/*
wr_rd_en控制读写状态和读写地址，addr为写入地址data为写入的数据

*/
module spi_ctrl #(
parameter  CPOL = 1'b0, 
parameter  CPHA = 1'b0,  
/*  CPOL CPHA   0	0	低（时钟空闲电平）	上升沿采样	下降沿更新
    CPOL CPHA	0	1	低	下降沿采样	上升沿更新
    CPOL CPHA	1	0	高	下降沿采样	上升沿更新
    CPOL CPHA	1	1	高	上升沿采样	下降沿更新
*/
parameter BITS_ORDER = 1'b0,  //数据传输位序：0（MSB）先发最高位，1（LSB）先发最低位
parameter ADDR_BIT = 'd16-1'b1,   //写地址和读写数据的位数
parameter DATA_BIT = 'd8-1'b1
)(
    input clk,
    input rst_n,
    input [ADDR_BIT:0] addr,   //地址与控制指令
    input [DATA_BIT:0] data,  //数据
    input GO,           //启动信号
    
    output SPI_CS,      //spi片选
    output SPI_SCLK,    //spi时钟
    inout SPI_IO,       //spi数据端口
    output MOSI,      //spi输出端口
//    input MISO,       //spi输入端口


    input DIV_PARAM,    //分频系数
    input cmd_valid,    //地址数据有效标志
    input wr_rd_en,     //读写使能，1写0读
    output reg done,        //数据传输完成信号
    output reg rd_done,     //读数据完成信号
    output reg rd_data


);

//    wire MOSI;
    wire MISO;
    reg io_en;
    reg wr_req;     //读写请求
    reg rd_req;
    wire ack;     //读写完成
    wire rd_ack;    //写读地址完成
    reg valid;
    reg [2:0] wait_cnt;
        
    reg [ADDR_BIT:0] addr_r;
    reg [DATA_BIT:0] data_r;
    wire Conv_Done;
    reg [DATA_BIT:0] data_in;
    reg [ADDR_BIT:0] data_addr;
    wire [DATA_BIT:0] data_out;

    assign SPI_IO = io_en? MOSI : 1'bz;     //写使能时SPI_IO输出，不写时输入。
    assign MISO = SPI_IO;

    
    always@(posedge clk, negedge rst_n)begin   
    if(!rst_n)begin
        addr_r <= 'b0;
        data_r <= 'b0;
    end else if(cmd_valid)begin
        addr_r <= addr;
        data_r <= data;
    end else begin
        addr_r <= addr_r;
        data_r <= data_r;
    end
    end
    
    always @(posedge clk, negedge rst_n)begin  //串口写完指令数据valid拉高，读写完成拉低
    if(!rst_n)          
        valid <= 0;
    else if(cmd_valid)
        valid <= 1;
    else if(done)
        valid <= 0;
    else
        valid <= valid;
    end
    
    localparam IDLE     = 0;
    localparam WR_RD    = 1;
    localparam WR_ADDR  = 2;
    localparam WR_DATA  = 3;
    localparam RD_ADDR  = 4;
    localparam RD_DATA  = 5;
    localparam DONE     = 6;
    localparam WAIT     = 7;
    
    reg [3:0] state;
    
    always@(posedge clk, negedge rst_n)begin   
    if(!rst_n)begin
        state <= IDLE;
        done <= 0;
        rd_done <= 0; 
        io_en <= 0;
        wr_req <= 0;
        rd_req <= 0;
        wait_cnt <= 0;
        data_in <= 0;
        rd_data <= 0;
        data_addr <= 0;
    end else if(GO)
        case(state)
            IDLE    :   begin           
                        if(valid)   //读写数据有效开始读写判断
                           state <=  WR_RD;
                        else 
                            state <= IDLE;
                        end
           WR_RD    :   begin       //读写判断
                        if(wr_rd_en)      //1写0读
                        begin
                            wr_req <= 1;
                            io_en <= 1;
                            state <= WR_ADDR;
                            data_addr <= addr_r;
                            data_in <= data_r;
                        end else begin
                            rd_req <= 1;
                            io_en <= 1;
                            state <= RD_ADDR;
                            data_addr <= addr_r;
                            data_in <= data_r;
                        end
                        end     
                        
            WR_ADDR :   begin           //写地址
                            state <= WR_DATA;   
                        end
                        
            WR_DATA :   begin       //写数据
                        if(ack)begin         
                            wr_req <= 0;
                            state <= DONE;                   
                        end else 
                            state <= WR_DATA; 
                        end
                        
            RD_ADDR :   begin       //写地址
                        if(rd_ack)
                            state <= RD_DATA;
                        end
            
            RD_DATA :   begin       //读数据
                        io_en <= 0;
                        if(ack)begin
                            rd_req <= 0;
                            rd_data <= data_out;
                            state <= DONE;
                            rd_done <= 1;
                        end else
                            state <= RD_DATA;
                        end
            
            DONE    :   begin 
                            rd_done <= 0;              
                            done <= 1;
                            io_en <= 1;
                            state <= WAIT;
                        end
                        
            WAIT    :   begin           //等待3周期
                        done <= 0;
                        if (wait_cnt == 2)begin 
                            state <= IDLE;
                            wait_cnt <= 0;
                        end else 
                            wait_cnt <= wait_cnt + 1;
                        end
    
            default :   state <= IDLE;
        endcase
    end
    
    
    spi_master #(
    .CPOL(CPOL), 
    .CPHA(CPHA),  
    .BITS_ORDER(BITS_ORDER),  
    .ADDR_BIT(ADDR_BIT),   
    .DATA_BIT(DATA_BIT)
    )
    spi_master(
    .clk(clk),
    .rst_n(rst_n),

    .CS(SPI_CS),
    .SCLK(SPI_SCLK),
    .MOSI(MOSI),
    .MISO(MISO),
    
    .wr_req(wr_req),       
    .rd_req(rd_req),
    .ack(ack),
    .rd_ack(rd_ack),
//    .En_Conv(En_Conv),
    .Conv_Done(Conv_Done),
//    .ADC_State(En_Conv),
    .DIV_PARAM(8'd16),   //sclk分频系数
    .data_addr(data_addr),
    .data_in(data_in),    
    .data_out(data_out)   

);

endmodule
