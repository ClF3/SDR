`timescale 1ns/1ps

module tb_iq_packetizer;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg enable = 1'b0;
    reg config_changed = 1'b0;
    reg [31:0] s_axis_tdata = 32'd0;
    reg s_axis_tvalid = 1'b0;
    wire s_axis_tready;
    wire [31:0] m_axis_tdata;
    wire [3:0]  m_axis_tkeep;
    wire m_axis_tvalid;
    reg  m_axis_tready = 1'b1;
    wire m_axis_tlast;
    wire [31:0] packet_seq;
    wire [31:0] packet_count;
    integer word_count = 0;
    integer payload_words = 0;
    integer last_count = 0;
    reg magic_ok = 1'b0;
    reg header_len_ok = 1'b0;

    always #5 clk = ~clk;

    iq_packetizer #(
        .STREAM_ID(16'd0),
        .FRAME_SAMPLES(16'd8)
    ) dut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .config_changed(config_changed),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .adc_timestamp_seed(64'd1234),
        .frequency_hz(64'd98500000),
        .iq_sample_rate_hz(32'd1000000),
        .bandwidth_hz(32'd250000),
        .flags(16'h0001),
        .gain_db_q8(16'sd0),
        .decimation(32'd250),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .packet_seq(packet_seq),
        .packet_count(packet_count)
    );

    always @(posedge clk) begin
        if (s_axis_tready) begin
            s_axis_tdata <= s_axis_tdata + 32'd1;
            s_axis_tvalid <= 1'b1;
        end else begin
            s_axis_tvalid <= 1'b0;
        end

        if (m_axis_tvalid && m_axis_tready) begin
            if (word_count == 0 && m_axis_tdata == 32'h5149_4453) begin
                magic_ok <= 1'b1;
            end
            if (word_count == 1 && m_axis_tdata == 32'h0040_0001) begin
                header_len_ok <= 1'b1;
            end
            if (word_count >= 16) begin
                payload_words <= payload_words + 1;
            end
            word_count <= word_count + 1;
            if (m_axis_tlast) begin
                last_count <= last_count + 1;
            end
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        rst = 1'b0;
        enable = 1'b1;
        repeat (120) @(posedge clk);

        if (!magic_ok || !header_len_ok || payload_words < 8 || last_count == 0 || m_axis_tkeep != 4'hf) begin
            $display("FAIL: magic=%0b header=%0b payload=%0d last=%0d", magic_ok, header_len_ok, payload_words, last_count);
            $finish(1);
        end

        $display("PASS: tb_iq_packetizer words=%0d packets=%0d", word_count, packet_count);
        $finish;
    end
endmodule
