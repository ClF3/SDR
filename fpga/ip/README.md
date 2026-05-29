# IP Notes

当前 RTL 不依赖外部 Vivado IP，NCO 使用项目内的 `cordic_sincos.v` 实现。

后续上板时可按资源和时序情况替换为 Xilinx IP：

```text
DDS Compiler       替换 nco + cordic_sincos
FIR Compiler       替换 cic_comp_fir
AXIS Data FIFO     可替换 `axis_async_fifo`，用于 PL packetizer 到 AXI DMA 的跨时钟缓冲
AXI DMA / VDMA     连接 m_axis_iq_tdata 到 PS DDR 或网络发送路径
```

替换 IP 前请先保持现有 testbench 通过，再逐个替换并重新仿真。
