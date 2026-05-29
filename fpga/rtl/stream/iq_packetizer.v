`timescale 1ns/1ps

module iq_packetizer #(
    parameter [15:0] STREAM_ID = 16'd0,
    parameter [15:0] FRAME_SAMPLES = 16'd256
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        config_changed,

    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,

    input  wire [63:0] adc_timestamp_seed,
    input  wire [63:0] frequency_hz,
    input  wire [31:0] iq_sample_rate_hz,
    input  wire [31:0] bandwidth_hz,
    input  wire [15:0] flags,
    input  wire signed [15:0] gain_db_q8,
    input  wire [31:0] decimation,

    output reg  [31:0] m_axis_tdata,
    output reg  [3:0]  m_axis_tkeep,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast,

    output reg  [31:0] packet_seq,
    output reg  [31:0] packet_count
);
    localparam [1:0] ST_IDLE    = 2'd0;
    localparam [1:0] ST_HEADER  = 2'd1;
    localparam [1:0] ST_PAYLOAD = 2'd2;

    localparam [31:0] SDR_IQ_MAGIC = 32'h5149_4453;
    localparam [15:0] VERSION = 16'd1;
    localparam [15:0] HEADER_LEN = 16'd64;
    localparam [15:0] FRAME_TYPE_IQ = 16'd1;
    localparam [15:0] SAMPLE_FORMAT_SC16 = 16'd1;
    localparam [15:0] FLAG_DISCONTINUITY = 16'h0004;
    localparam [15:0] FLAG_CONFIG_CHANGED = 16'h0008;

    reg [1:0]  state;
    reg [4:0]  header_index;
    reg [15:0] payload_count;
    reg [63:0] packet_timestamp;
    reg [63:0] next_packet_timestamp;
    reg [63:0] frequency_latched;
    reg [31:0] rate_latched;
    reg [31:0] bandwidth_latched;
    reg [31:0] decimation_latched;
    reg [15:0] flags_latched;
    reg signed [15:0] gain_latched;
    reg        first_packet;
    wire       out_ready;
    wire [31:0] payload_bytes;
    wire [63:0] timestamp_step;
    wire [15:0] packet_flags;

    assign out_ready = !m_axis_tvalid || m_axis_tready;
    assign s_axis_tready = (state == ST_PAYLOAD) && out_ready;
    assign payload_bytes = {14'd0, FRAME_SAMPLES, 2'b00};
    assign timestamp_step = decimation_latched * FRAME_SAMPLES;
    assign packet_flags = flags_latched |
                          (first_packet ? (FLAG_DISCONTINUITY | FLAG_CONFIG_CHANGED) : 16'd0);

    always @(posedge clk) begin
        if (rst) begin
            state                 <= ST_IDLE;
            header_index          <= 5'd0;
            payload_count         <= 16'd0;
            packet_timestamp      <= 64'd0;
            next_packet_timestamp <= 64'd0;
            frequency_latched     <= 64'd0;
            rate_latched          <= 32'd0;
            bandwidth_latched     <= 32'd0;
            decimation_latched    <= 32'd1;
            flags_latched         <= 16'd0;
            gain_latched          <= 16'sd0;
            first_packet          <= 1'b1;
            packet_seq            <= 32'd0;
            packet_count          <= 32'd0;
            m_axis_tdata          <= 32'd0;
            m_axis_tkeep          <= 4'hf;
            m_axis_tvalid         <= 1'b0;
            m_axis_tlast          <= 1'b0;
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
            end

            if (!enable) begin
                state         <= ST_IDLE;
                header_index  <= 5'd0;
                payload_count <= 16'd0;
                first_packet  <= 1'b1;
            end else if (config_changed) begin
                state                 <= ST_IDLE;
                header_index          <= 5'd0;
                payload_count         <= 16'd0;
                packet_seq            <= 32'd0;
                packet_timestamp      <= adc_timestamp_seed;
                next_packet_timestamp <= adc_timestamp_seed;
                first_packet          <= 1'b1;
            end else if (out_ready) begin
                case (state)
                    ST_IDLE: begin
                        packet_timestamp      <= next_packet_timestamp;
                        frequency_latched     <= frequency_hz;
                        rate_latched          <= iq_sample_rate_hz;
                        bandwidth_latched     <= bandwidth_hz;
                        decimation_latched    <= (decimation == 32'd0) ? 32'd1 : decimation;
                        flags_latched         <= flags;
                        gain_latched          <= gain_db_q8;
                        header_index          <= 5'd0;
                        payload_count         <= 16'd0;
                        state                 <= ST_HEADER;
                    end

                    ST_HEADER: begin
                        m_axis_tvalid <= 1'b1;
                        m_axis_tkeep  <= 4'hf;
                        m_axis_tlast  <= 1'b0;

                        case (header_index)
                            5'd0:  m_axis_tdata <= SDR_IQ_MAGIC;
                            5'd1:  m_axis_tdata <= {HEADER_LEN, VERSION};
                            5'd2:  m_axis_tdata <= {STREAM_ID, FRAME_TYPE_IQ};
                            5'd3:  m_axis_tdata <= packet_seq;
                            5'd4:  m_axis_tdata <= packet_timestamp[31:0];
                            5'd5:  m_axis_tdata <= packet_timestamp[63:32];
                            5'd6:  m_axis_tdata <= frequency_latched[31:0];
                            5'd7:  m_axis_tdata <= frequency_latched[63:32];
                            5'd8:  m_axis_tdata <= rate_latched;
                            5'd9:  m_axis_tdata <= bandwidth_latched;
                            5'd10: m_axis_tdata <= {FRAME_SAMPLES, SAMPLE_FORMAT_SC16};
                            5'd11: m_axis_tdata <= {gain_latched, packet_flags};
                            5'd12: m_axis_tdata <= decimation_latched;
                            5'd13: m_axis_tdata <= payload_bytes;
                            5'd14: m_axis_tdata <= 32'd0;
                            default: m_axis_tdata <= 32'd0;
                        endcase

                        if (header_index == 5'd15) begin
                            header_index <= 5'd0;
                            state        <= ST_PAYLOAD;
                        end else begin
                            header_index <= header_index + 5'd1;
                        end
                    end

                    ST_PAYLOAD: begin
                        if (s_axis_tvalid) begin
                            m_axis_tdata  <= s_axis_tdata;
                            m_axis_tkeep  <= 4'hf;
                            m_axis_tvalid <= 1'b1;

                            if (payload_count == FRAME_SAMPLES - 16'd1) begin
                                m_axis_tlast          <= 1'b1;
                                payload_count         <= 16'd0;
                                state                 <= ST_IDLE;
                                packet_seq            <= packet_seq + 32'd1;
                                packet_count          <= packet_count + 32'd1;
                                next_packet_timestamp <= packet_timestamp + timestamp_step;
                                first_packet          <= 1'b0;
                            end else begin
                                payload_count <= payload_count + 16'd1;
                            end
                        end
                    end

                    default: begin
                        state <= ST_IDLE;
                    end
                endcase
            end
        end
    end
endmodule
