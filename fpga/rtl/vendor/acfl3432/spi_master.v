`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////////
// Company       : 武汉芯路恒科技有限公司
//                 http://xiaomeige.taobao.com
// Web           : http://www.corecourse.cn
// 
// Create Date: 2025/09/01 09:21:55
// Design Name: 
// Module Name: spi_master
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

module spi_master #(
parameter  CPOL = 1'b0, 
parameter  CPHA = 1'b0,  
/*  CPOL CPHA   0	0	低（时钟空闲电平）	上升沿采样	下降沿更新
    CPOL CPHA	0	1	低	下降沿采样	上升沿更新
    CPOL CPHA	1	0	高	下降沿采样	上升沿更新
    CPOL CPHA	1	1	高	上升沿采样	下降沿更新
*/
parameter BITS_ORDER = 1'b1,  //数据传输位序：0（MSB）先发最高位，1（LSB）先发最低位
parameter ADDR_BIT = 'd16-1'b1,   //写地址和读写数据的位数
parameter DATA_BIT = 'd16-1'b1
)(
    input clk,
    input rst_n,

    output reg CS,
    output reg SCLK,
    output reg MOSI,
    input MISO,
    
    input wr_req,          
    input rd_req,
    output reg ack,
    output rd_ack,      //写读地址完成信号
//    input En_Conv,	//使能单次转换，该信号为单周期有效，高脉冲使能一次转换
    output reg Conv_Done,   //转换完成信号，完成转换后产生一个时钟周期的高脉冲
//    output ADC_State,	//ADC工作状态，ADC处于转换时为低电平，空闲时为高电平
    input [7:0] DIV_PARAM,	//时钟分频设置，实际SCLK时钟 频率 = fclk / （DIV_PARAM * 2）
    input [ADDR_BIT:0] data_addr,  //输入地址或控制命令
    input [DATA_BIT:0] data_in,    //输入数据上机位>SPI
    output reg [DATA_BIT:0] data_out   //输出数据SPI>上位机

);

    reg [DATA_BIT:0] data_in_reg;  //输入数据寄存器
    reg [ADDR_BIT:0] data_addr_reg;//输入地址寄存器
    reg [15:0] DIV_CNT;
    reg SCLK2X;//2倍SCLK的采样时钟
//	reg [5:0] SCLK_GEN_CNT;//SCLK生成与序列机计数器
	reg [7:0] clk_edge_cnt;//SCLK边沿计数器
	reg [ADDR_BIT:0] addr_cnt; //写地址和读写数据计数器
	reg [DATA_BIT:0] data_cnt;
	reg [3:0] wait_cnt;        //cs至SCLK延迟计数
    reg SCLK_state;             //序列机控制时钟
    reg en;

		
    //产生ADC工作状态指示信号
//	assign ADC_State = CS;

    //产生使能转换信号
	always@(posedge clk, negedge rst_n)begin
	if(!rst_n)
		en  <= 1'b0;
	else if((wr_req || rd_req))
		en  <= 1'b1;
	else if(Conv_Done)
		en  <= 1'b0;
	else
		en  <= en;
	end
	
    //生成2倍SCLK使能时钟计数器
	always@(posedge clk, negedge rst_n)begin
	if(!rst_n)
		DIV_CNT  <= 8'd0;
	else if(en)begin
		if(DIV_CNT == (DIV_PARAM - 1'b1))
			DIV_CNT  <= 8'd0;
		else 
			DIV_CNT  <= DIV_CNT + 1'b1;
	end else	
		DIV_CNT  <= 8'd0;
    end

	//生成2倍SCLK使能时钟和边沿计数器
	always@(posedge clk, negedge rst_n)begin
	if(!rst_n)begin
		SCLK2X  <= 1'b0;
		SCLK_state <= 0;
    end
	else if(en && (DIV_CNT == (DIV_PARAM - 1'b1)))begin
		SCLK2X  <= 1'b1;
		SCLK_state <= ~SCLK_state;
	end else begin  
		SCLK2X  <= 1'b0;
		SCLK_state <= SCLK_state;
    end
    end
    
    localparam IDLE  = 0;
    localparam WAIT  = 1;
    localparam WR_AD = 2;
    localparam WR_DA = 3;
    localparam RD_AD = 4;
    localparam RD_DA = 5;
    localparam DONE  = 6;
    reg [2:0] state;
    
    
    //生成SCLK时钟与时钟边沿计数器
    always@(posedge clk, negedge rst_n)begin
	if(!rst_n)begin
		SCLK  <= CPOL;
		clk_edge_cnt <= 8'd0;
	end else if((state==WR_AD || state==WR_DA || state==RD_AD || state==RD_DA)  && (DIV_CNT == (DIV_PARAM - 1'b1)))begin
		SCLK  <= ~SCLK;
		clk_edge_cnt <= clk_edge_cnt + 1;
	end else begin
		SCLK  <= SCLK;
		clk_edge_cnt <= clk_edge_cnt;
    end
    end
    
    always@(posedge clk, negedge rst_n)begin         //写地址，写数据
    if(!rst_n)begin
		CS <= 1'b1;
        MOSI <= 1'b1;
        ack <= 1'b0;
        data_in_reg <= 'd0;
		data_addr_reg <= 'b0;
		data_out <= 'b0;
		data_cnt <= 'd0;
		addr_cnt <= 'd0;
		wait_cnt <= 'd0;
		state <= 'd0;
		Conv_Done <= 'd0;
    end else 
        case(state)
            IDLE    :   begin
                        Conv_Done <= 'd0;
                        wait_cnt <= 'd0;
                        if(wr_req || rd_req)begin                 //
                            state <= WAIT;
                            CS <= 1'b0;
                            data_addr_reg <= data_addr;
                            data_in_reg <= data_in; 
                        end else 
                            state <= state;
                        end
                        
            WAIT :   begin           //CS到SCLK的延时，具体大小根据时序而定
                        if(SCLK2X)begin
                        if(wait_cnt == 2)begin
                            if(wr_req)begin
                                if((CPHA ^ CPOL) == 0)begin        //CPHA ^ CPOL为0时，数据要提前放置到总线上
                                   if(BITS_ORDER == 0)begin         //判断读写地址 数据位序
                                        state <= WR_AD;
                                        MOSI <= data_addr_reg[ADDR_BIT]; 
                                        data_addr_reg <= {data_addr_reg[ADDR_BIT-1:0],1'b0};
                                    end else begin
                                        state <= WR_AD;
                                        MOSI <= data_addr_reg[0]; 
                                        data_addr_reg <= {1'b0,data_addr_reg[ADDR_BIT:1]};
                                    end
                                    end
                                else begin
                                    state <= WR_AD;
                                end
                            end else if(rd_req)begin
                                if((CPHA ^ CPOL) == 0)begin
                                    if(BITS_ORDER == 0)begin
                                        state <= RD_AD;
                                        MOSI <= data_addr_reg[ADDR_BIT]; 
                                        data_addr_reg <= {data_addr_reg[ADDR_BIT-1:0],1'b0};
                                    end else begin
                                        state <= RD_AD;
                                        MOSI <= data_addr_reg[0]; 
                                        data_addr_reg <= {1'b0,data_addr_reg[ADDR_BIT:1]};
                                    end    
                                    end
                                else begin
                                    state <= RD_AD;
                                end
                            end else
                                state <= IDLE;
                            end
                        else
                            wait_cnt <= wait_cnt + 1;
                        end
                        end
            
            WR_AD   :   begin           //写地址
                        if(SCLK2X)begin
                        if(clk_edge_cnt[0] == (CPHA ^ CPOL))
                            if(addr_cnt < ADDR_BIT)begin
                                if(BITS_ORDER == 0)begin
                                    MOSI <= data_addr_reg[ADDR_BIT];      
                                    data_addr_reg <= {data_addr_reg[ADDR_BIT-1:0],1'b0};
                                    addr_cnt <= addr_cnt + 1;
                                end else begin
                                    MOSI <= data_addr_reg[0];      
                                    data_addr_reg <= {1'b0,data_addr_reg[ADDR_BIT:1]};
                                    addr_cnt <= addr_cnt + 1;
                                end
                            end else if((CPHA ^ CPOL) == 0)begin 
                                if(BITS_ORDER == 0)begin
                                    state <= WR_DA;
                                    MOSI <= data_in_reg[DATA_BIT];     
                                    data_in_reg <= {data_in_reg[DATA_BIT-1:0],1'b0};
                                    addr_cnt <= 0;
                                end else begin
                                    state <= WR_DA;
                                    MOSI <= data_in_reg[0];     
                                    data_in_reg <= {1'b0,data_in_reg[DATA_BIT:1]};
                                    addr_cnt <= 'd0;
                                end
                            end  else begin
                                state <= WR_DA;
                                addr_cnt <= 'd0;  
                        end else begin
                            addr_cnt <= addr_cnt;
                            MOSI <= MOSI;
                            data_addr_reg <= data_addr_reg;
                        end
                        end
                        end
                        
            WR_DA   :   begin           //写数据
                        if(SCLK2X)begin
                        if(clk_edge_cnt[0] == (CPHA ^ CPOL))
                            if(data_cnt < DATA_BIT)begin
                                if(BITS_ORDER == 0)begin
                                    MOSI <= data_in_reg[DATA_BIT];      
                                    data_in_reg <= {data_in_reg[DATA_BIT-1:0],1'b0};
                                    data_cnt <= data_cnt + 1;
                                end else begin
                                    MOSI <= data_in_reg[0];      
                                    data_in_reg <= {1'b0,data_in_reg[DATA_BIT:1]};
                                    data_cnt <= data_cnt + 1;
                                end
                            end else begin 
                                state <= DONE;
                                ack <= 'd1;
                                data_cnt <= 'd0;
                            end 
                        else begin
                            data_cnt <= data_cnt;
                            MOSI <= MOSI;
                            data_in_reg <= data_in_reg;
                        end
                        end
                        end
                        
            RD_AD   :   begin           //写地址
                        if(SCLK2X)begin
                        if(clk_edge_cnt[0] == (CPHA ^ CPOL))
                            if(addr_cnt < ADDR_BIT)begin
                                if(BITS_ORDER == 0)begin
                                    MOSI <= data_addr_reg[ADDR_BIT];      
                                    data_addr_reg <= {data_addr_reg[ADDR_BIT-1:0],1'b0};
                                    addr_cnt <= addr_cnt + 1;
                                end else begin
                                    MOSI <= data_addr_reg[0];      
                                    data_addr_reg <= {1'b0,data_addr_reg[ADDR_BIT:1]};
                                    addr_cnt <= addr_cnt + 1;
                                end
                            end else if((CPHA ^ CPOL) == 0)begin 
                                if(BITS_ORDER == 0)begin
                                    state <= RD_DA;
                                    data_out <= {data_out[DATA_BIT-1:0],MISO}; 
                                    addr_cnt <= 0;
                                end else begin
                                    state <= RD_DA;
                                    data_out <= {MISO,data_out[DATA_BIT:1]}; 
                                    addr_cnt <= 'd0;
                                end
                            end  else begin
                                state <= RD_DA;
                                addr_cnt <= 'd0;  
                        end else begin
                            addr_cnt <= addr_cnt;
                            MOSI <= MOSI;
                            data_addr_reg <= data_addr_reg;
                        end
                        end
                        end
                        
             RD_DA   :   begin       //读数据
                        if(SCLK2X)begin
                        if(clk_edge_cnt[0] == (CPHA ^ CPOL))
                            if(data_cnt < DATA_BIT) begin
                                if(BITS_ORDER == 0)begin
                                    data_out <= {data_out[DATA_BIT-1:0],MISO};      
                                    data_cnt <= data_cnt + 1;
                                end else begin
                                    data_out <= {MISO,data_out[DATA_BIT:1]};      
                                    data_cnt <= data_cnt + 1;
                                end
                            end else begin 
                                state <= DONE;  
                                ack <= 'd1;
                                data_cnt <= 'd0;
                            end
                        else begin
                            data_cnt <= data_cnt;
                            data_out <= data_out;
                        end
                        end
                        end
                        
            DONE    :   begin
                            ack <= 0;
                            if(SCLK2X)begin             //保持半个SCLK周期后拉高CS
                                state <= IDLE;
                                CS <= 1'b1;
                                Conv_Done <= 'b1;
                            end
                        end
           
           default  :   state <= IDLE;
       endcase   
    end    
    
    reg [7:0] next_state;
    reg rd_state;

    // 产生读ack信号，用于控制SPI_IO方向
    always@(posedge clk, negedge rst_n)begin         
    if(!rst_n)begin
        next_state <= IDLE;
        rd_state <= 1'b0;
    end else begin
        next_state <= state;
        // 记录长状态是否在上一周期存在
        rd_state <= (next_state == RD_DA);
    end
    end

    // 生成脉冲：当前状态是LONG_STATE且上一周期不是
    assign rd_ack = (next_state == RD_DA) && !rd_state;
    
endmodule
