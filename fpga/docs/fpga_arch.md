# FPGA Architecture

第一版 FPGA 架构聚焦单路 DDC + 网络 IQ payload 生成：

```text
acfl3432_adc_frontend
  -> IBUFDS/IDDRE1 recover ch0/ch1 14-bit samples
  -> channel select
  -> adc_format_convert
  -> dc_offset_remove
  -> adc_level_monitor
  -> ddc_core
      -> nco + cordic_sincos
      -> mixer_real_to_iq
      -> cic_decimator I/Q
      -> iq_gain_sat
  -> iq_packetizer
      -> 64 byte SDIQ header
      -> 256 SC16 IQ samples
      -> AXI-Stream TLAST packet for AXI DMA
```

CM3432 SPI 上电配置复用第 11 章工程的：

```text
lut_config
spi_ctrl
spi_master
```

## Clock Domains

当前顶层包含两个主要时钟域：

```text
s_axi_aclk       AXI-Lite 控制寄存器
adc_sample_clk   CM3432 DCO，经 adc1_clk_p/n IBUFDS 恢复
```

控制配置通过 `config_sync` 从 `s_axi_aclk` 同步到 `adc_sample_clk`。状态计数器由 ADC 时钟域产生，PS 侧读取用于状态上报。

`sdr_top` 在 `m_axis_iq_*` 前内置 `axis_async_fifo`。PL packetizer 写入端在
`adc_sample_clk` 域，DMA/PS 读取端在 `s_axi_aclk` 域，避免把 AXI-Stream
valid/ready 直接跨时钟连接。

## Sampling And Tuning

ADC 采样率按 250 MSPS 设计，NCO 相位累加器 32 bit：

```text
freq_word = round(f_tune / 250e6 * 2^32)
```

DDC 中 Q 路使用 `real * -sin`，输出为 `{I, Q}` 的 SC16 complex sample。

## Packetization

`iq_packetizer` 按 `network_protocol.md` 生成 `SdrIqHeader`：

```text
magic = 0x51494453  // SDIQ
header_len = 64
sample_count = 256
payload_bytes = 1024
```

每个 packet 的 `adc_timestamp` 按：

```text
timestamp += decimation * 256
```

维护连续性。重新配置或启用 stream 会清零 sequence，并在第一个包设置
`DISCONTINUITY | CONFIG_CHANGED`。

SC16 payload 在 AXI-Stream 32-bit word 内按 `{Q[15:0], I[15:0]}` 打包。AXI
byte lane 0 是 `tdata[7:0]`，因此经 DMA/UDP 后的网络字节序是协议要求的
`int16_le I` 后接 `int16_le Q`。

## Status

`adc_level_monitor` 按窗口统计 peak 和 mean-square，同时累加：

```text
ADC OR
ADC clip
DDC SC16 saturation
IQ FIFO/stream overflow
```

PS 侧读取这些寄存器后组成 UDP status JSON。
