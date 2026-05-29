# SDR FPGA Verilog Project

本工程实现 `SDR总体设计.md` 中 FPGA/PL 侧第一版最小闭环，并已按以下资料适配：

- `第11章 基于 AXI DMA 的CM3432双通道数据采集TCP传输系统/`
- `network_protocol.md`

当前链路：

```text
ACFL3432/CM3432 FMC 差分接口
  -> IBUFDS + IDDRE1 恢复双通道 14-bit 样点
  -> ADC signed 格式转换 / DC offset removal / peak/rms/clip 监控
  -> 单路 DDC0，支持选择 RF1/RF2
  -> CIC 抽取到 125k/250k/500k/1M IQ
  -> SC16 IQ 饱和
  -> 64 字节 SDIQ UDP payload header + 256 个 IQ 样点
  -> AXI-Stream 给 AXI DMA S2MM
  -> PS 端按 UDP 9001 发给树莓派
```

PS 端 TCP/UDP 协议栈仍由 Zynq UltraScale+ PS/lwIP 实现。FPGA 侧负责把 `network_protocol.md` 规定的二进制 IQ UDP payload 预打包成 DMA 数据块。

## 目录

```text
rtl/top/                 顶层和 SDR PL core
rtl/adc/                 ACFL3432 差分采样、SPI 配置、ADC 格式转换
rtl/vendor/acfl3432/     从第 11 章工程导入的 CM3432 SPI 配置模块
rtl/dsp/                 NCO、CORDIC、Mixer、CIC、IQ 饱和
rtl/monitor/             ADC 电平/过载统计
rtl/ctrl/                AXI-Lite CSR 寄存器
rtl/stream/              SDIQ packetizer 和 AXI-Stream 辅助模块
rtl/util/                reset/sync/CDC/skid buffer
sim/tb/                  Icarus/Vivado 可跑的 testbench
scripts/                 仿真、lint、Vivado Tcl
constraints/             AC920 + ACFL3432 管脚和时序约束
docs/                    架构、寄存器、包格式说明
```

## 顶层

Vivado 顶层：

```text
rtl/top/sdr_top.v
```

默认器件与第 11 章 demo 一致：

```text
xczu4ev-sfvc784-2-i
```

外部 ACFL3432 端口沿用 vendor demo 命名，便于复用 XDC：

```text
adc1_clk_p_0 / adc1_clk_n_0          CM3432 DCO
adc1_data_p_0[13:0] / adc1_data_n_0  CM3432 14 对差分数据
adc_clk_p_0 / adc_clk_n_0            FPGA 输出给 ADC 的采样时钟
adc1_spi_ce_0 / adc1_spi_sclk_0 / adc1_spi_io_0
reset_n_0
```

系统侧接口：

```text
s_axi_*          PS 通过 AXI-Lite 配置 DDC/状态寄存器
m_axis_iq_*      SDIQ UDP payload AXI-Stream，接 AXI DMA S2MM
adc_ref_clk      给 ADC 的 250 MHz 参考/采样时钟
spi_clk_50m      CM3432 SPI 配置时钟
```

`m_axis_iq_tdata` 输出的不是裸 IQ，而是完整 UDP payload：

```text
16 个 32-bit word 的 SdrIqHeader，64 字节
256 个 32-bit word 的 SC16 IQ payload，1024 字节
TLAST 在最后一个 IQ word
```

总长度为 `1088 bytes`，符合 `network_protocol.md` 的默认 IQ UDP payload。

`m_axis_iq_*` 已经通过顶层内置的 `axis_async_fifo` 同步到 `s_axi_aclk`
域，适合接 PS block design 里的 AXI DMA S_AXIS。`sdr_pl_core` 内部 packetizer
仍在 ADC sample clock 域工作。

注意：这里的“UDP payload”只是 PL 侧预打包的数据块。当前 standalone
`sdr_top` 不包含 Ethernet MAC、IP 栈、TCP server、UDP sender、AXI DMA 或 PS
block design；烧录 bitstream 后不会自动在网络上监听 `9000`。真实上板链路还
需要 AC920 PS 端程序把 AXI-Lite、AXI DMA 和 GEM/lwIP 或 Linux socket 接起来。

## 寄存器

详细表见 [docs/reg_map.md](docs/reg_map.md)。

常用 `set_rx` 映射：

```text
frequency_hz      -> DDC0_FREQ_HZ_L/H + DDC0_FREQ_WORD
iq_sample_rate_hz -> DDC0_IQ_RATE + DDC0_DECIM
bandwidth_hz      -> DDC0_BANDWIDTH
adc_channel       -> DDC0_CONTROL bit1
enable            -> DDC0_CONTROL bit0 + CONTROL bit0
sample_format     -> 固定 SC16_LE
```

NCO 频率字：

```text
freq_word = round(frequency_hz / 250000000 * 2^32)
```

支持的抽取率：

| IQ rate | Decimation | Samples/packet |
|---:|---:|---:|
| `125000` | `2000` | `256` |
| `250000` | `1000` | `256` |
| `500000` | `500` | `256` |
| `1000000` | `250` | `256` |

## 本地验证

需要 `iverilog` 和 `verilator`：

```bash
cd fpga
./scripts/run_sim.sh
./scripts/run_lint.sh
./scripts/run_verilator.sh
```

启动 Verilator + TCP/UDP 本机联合仿真 endpoint：

```bash
cd fpga
./scripts/run_cosim_server.sh --bind 127.0.0.1 --control-port 9000
```

这个 endpoint 用 C++ harness 模拟 AC920 PS 的 TCP JSON/UDP socket 层，但 IQ
UDP payload 来自 Verilated `sdr_pl_core` 的 AXI-Stream 输出。

当前 testbench：

```text
tb_nco
tb_adc_level_monitor
tb_iq_packetizer
tb_ddc_core
tb_sdr_pl_core
```

## Vivado 运行流程

创建工程：

```bash
cd fpga
vivado -mode batch -source scripts/vivado_create_project.tcl
```

指定器件时：

```bash
FPGA_PART=xczu4ev-sfvc784-2-i vivado -mode batch -source scripts/vivado_create_project.tcl
```

工程输出：

```text
build/vivado/sdr_fpga/sdr_fpga.xpr
```

跑综合：

```bash
vivado -mode batch -source scripts/vivado_build_bitstream.tcl
```

补齐 PS block design 连接后跑实现和 bitstream：

```bash
RUN_IMPL=1 vivado -mode batch -source scripts/vivado_build_bitstream.tcl
```

bitstream 输出：

```text
build/vivado/sdr_fpga.bit
```

## 与第 11 章工程集成

第 11 章原工程是：

```text
ADC -> fifo2axis_write -> AXI DMA -> DDR -> PS TCP
```

本工程替换为：

```text
ADC -> sdr_pl_core -> iq_packetizer -> AXI DMA -> DDR -> PS UDP 9001
```

集成时保留 PS、AXI DMA、GEM/lwIP 的方式；把原 `fifo2axis_write` 的 AXI DMA S_AXIS 输入改接 `m_axis_iq_*`。PS 端收到 DMA buffer 后不需要再拼 IQ 包头，直接把 1088 字节作为 UDP payload 发送到树莓派 IQ 端口。

### AC920 vendor demo overlay

如果本机有 vendor 工程：

```text
~/Downloads/AC920_CM3432_DualChannel_TCP
```

可以用脚本直接复制 vendor 工程并套用本项目 SDR 数据路径：

```bash
cd /Users/tianyi/repos/SDR
bash fpga/scripts/prepare_ac920_vendor_project.sh ~/Downloads/AC920_CM3432_DualChannel_TCP
```

该命令需要在 Vivado shell 中运行，或先 source `settings64.sh` 让 `vivado`
出现在 `PATH` 中。

脚本会生成：

```text
fpga/build/ac920_vendor_sdr/CM3432_DualChannel_TCP.xpr
```

这个工程保留 vendor 的 PS/GEM/DDR/clock/reset/XDC/ADC SPI 顶层，只在
`sys.bd` 中把旧的：

```text
adc_sample_ctrl_0 + fifo2axis_write_0
```

替换成：

```text
sdr_vendor_bd_core_0
```

然后继续在 Vivado 中跑 `Generate Bitstream`、`Export Hardware` 即可。若
Vivado 自动连线失败，打开 `sys.bd` 手动检查：

```text
sdr_vendor_bd_core_0/M_AXIS  -> axi_dma_0/S_AXIS_S2MM
sdr_vendor_bd_core_0/S00_AXI -> axi_smc/M00_AXI
din_0/din_comb_0/dvalid_0    -> sdr_vendor_bd_core_0
```

## 当前边界

已完成：

```text
ACFL3432 差分 ADC 输入
CM3432 SPI 上电配置导入
单路 DDC0
SDIQ 64 字节头 + SC16 payload packetizer
AXI-Lite 控制/状态寄存器
AC920/ACFL3432 XDC 初版
仿真和 lint
```

未完成：

```text
PS 端 JSON Lines TCP 控制服务
PS 端 UDP 9001/9003 发送代码
TCP raw ADC capture 9004
UDP PSD 9002 / 宽带 FFT
第二路 DDC
```
