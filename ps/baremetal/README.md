# AC920 Bare-Metal PS Bridge

This directory contains the Milestone 1 PS-side bridge for the AC920 Zynq PS.
It is intentionally kept independent of a specific vendor demo tree so it can
be copied into the Vitis/lwIP project generated from the real Vivado XSA.

The FPGA PL does not implement TCP/IP. The PS application must:

1. listen for TCP JSON Lines control on port `9000`
2. program the PL AXI-Lite registers
3. receive 1088-byte IQ packets from AXI DMA S2MM
4. forward those packets over UDP port `9001`
5. emit JSON status over UDP port `9003`

PSD/UDP `9002` is deliberately reported as unsupported in this Milestone 1
bridge. The Raspberry Pi hardware profile disables PSD and uses local spectrum
from IQ packets until the FPGA PSD path exists.

## Source Files

- `src/sdr_control.c`: JSON command dispatcher and register programming.
- `src/sdr_control.h`: context and functions called by the TCP/DMA glue.
- `src/sdr_regs.h`: AXI-Lite register map matching `fpga/docs/reg_map.md`.
- `src/sdr_hw.h`: hardware/network hooks that the vendor demo must provide.
- `src/sdr_hw_ac920.c`: Vitis/lwIP adapter for AXI-Lite, simple-mode AXI DMA
  S2MM, UDP IQ/status send, and `sys_now()` timing.
- `src/sdr_hw_ac920.h`: polling helpers for DMA completion and periodic status.
- `src/sdr_hw_stubs.c`: weak host-build stubs for syntax tests; replace or
  override these in the Vitis project.

## Commands Implemented

- `hello`: accepts protocol v1 and UDP destination ports.
- `ping`: heartbeat response.
- `get_status`: returns ADC, stream, frontend, and network status.
- `set_frontend`: validates and stores requested frontend settings. Real RF
  GPIO/SPI control still needs board-specific implementation.
- `set_rx`: programs DDC0 registers and starts IQ DMA.
- `set_psd`: accepts disable; returns unsupported for enable.
- `stop_all`: stops DMA and disables DDC/core registers.

## Required Vendor Demo Hooks

`src/sdr_hw_ac920.c` implements the functions declared in `src/sdr_hw.h` using
standard Xilinx bare-metal drivers. In Vitis, compile this file with the app and
do not rely on the weak host stubs.

Before compiling, check `xparameters.h` from the exported XSA. If the generated
macro names do not match the fallbacks in `sdr_hw_ac920.c`, add these compiler
symbols or edit the top of that file:

```c
#define SDR_AXI_BASEADDR        XPAR_<SDR_TOP_INSTANCE>_S_AXI_BASEADDR
#define SDR_AXI_DMA_DEVICE_ID   XPAR_<AXI_DMA_INSTANCE>_DEVICE_ID
```

The board-specific functions are:

```c
int sdr_hw_init(void);
uint64_t sdr_hw_millis(void);
uint32_t sdr_hw_read_reg(uint32_t offset);
void sdr_hw_write_reg(uint32_t offset, uint32_t value);
void sdr_hw_read_status(sdr_hw_status_t *status);
int sdr_hw_start_iq_dma(void);
void sdr_hw_stop_iq_dma(void);
int sdr_hw_set_udp_peer(const sdr_udp_peer_t *peer);
int sdr_hw_udp_send_iq(const void *packet, size_t length);
int sdr_hw_udp_send_status(const void *payload, size_t length);
```

Current mappings:

- `sdr_hw_read_reg/write_reg`: `Xil_In32/Xil_Out32(SDR_AXI_BASEADDR + offset)`.
- `sdr_hw_start_iq_dma`: submits one simple-mode S2MM receive buffer.
- `sdr_hw_udp_send_iq`: `udp_sendto()` the DMA buffer to the peer from `hello`.
- `sdr_hw_udp_send_status`: `udp_sendto()` JSON status to UDP `9003`.
- `sdr_hw_millis`: lwIP `sys_now()`.

In a polling lwIP echo-server style main loop, call:

```c
sdr_hw_ac920_poll_iq_dma(&g_sdr);
sdr_hw_ac920_poll_status(&g_sdr, 200);
```

These helpers forward a completed 1088-byte S2MM packet and re-arm the DMA, then
send periodic JSON status. If you switch to DMA interrupts later, the interrupt
handler can call `sdr_control_forward_iq_packet()` directly and then re-submit
the S2MM transfer.

For each TCP line received on port `9000`, call:

```c
char response[2048];
size_t n = sdr_control_handle_line(&g_sdr, line, response, sizeof(response));
tcp_write(tpcb, response, (u16_t)n, TCP_WRITE_FLAG_COPY);
```

Set the TCP peer IP before handling `hello` if the request does not include an
explicit `udp.destination_ip`:

```c
sdr_control_set_peer_ip(&g_sdr, peer_ip_string);
```

## Bring-Up Order

1. Build Vivado block design from the vendor AC920 demo:
   - Zynq PS GEM enabled
   - AXI DMA S2MM connected to `sdr_top.m_axis_iq_*`
   - AXI-Lite mapped to `sdr_top.s_axi_*`
   - FCLK/clocking and reset matched to the board demo
2. Export XSA including bitstream.
3. Create/modify a Vitis bare-metal lwIP app from that XSA.
4. Add these sources and implement `sdr_hw.h` hooks.
5. Fix the board IP to `192.168.10.2`; Raspberry Pi is `192.168.10.1`.
6. Package SD boot image with FSBL/PMUFW/bitstream/ELF.
7. On the Raspberry Pi, run:

```bash
python3 tools/network_probe.py 192.168.10.2 --skip-psd
```

The expected first acceptance is TCP `hello/ping`, UDP status, UDP IQ, then
`stop_all` without packet loss.
