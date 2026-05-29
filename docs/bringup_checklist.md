# Bring-Up Checklist

This is the debug path for AC920 + ACFL3432 + Raspberry Pi networking.

## Current Repository State

The `fpga/` design is a PL data-path design. It produces AXI-Stream packets that
already contain the 64 byte SDIQ header plus SC16 payload, but it does not
instantiate or implement Ethernet, TCP, UDP, ARP, DHCP, AXI DMA, or a Zynq PS
software stack.

So a standalone bitstream can synthesize and be programmed, but it will not open
TCP port `9000` or send UDP packets by itself. Network connectivity requires a
PS-side bridge:

```text
Raspberry Pi TCP 9000
  -> AC920 PS TCP JSON server
  -> AXI-Lite writes to sdr_top CSR registers
  -> AXI DMA receives s_axi_aclk-domain m_axis_iq_* from PL
  -> AC920 PS sends UDP 9001/9003 to Raspberry Pi
```

PSD UDP `9002` and raw capture TCP `9004` are protocol-defined, but the current
FPGA README still marks them as not implemented on the board path.

## 1. Basic Network Checks

On the Raspberry Pi, use the AC920 PS IP address, not `127.0.0.1`:

```sh
ping <ac920-ps-ip>
nc -vz <ac920-ps-ip> 9000
python tools/network_probe.py <ac920-ps-ip> --timeout 3
```

Expected result:

```text
OK hello
OK ping
OK status UDP
OK IQ UDP
```

If TCP connect fails or times out, debug the AC920 PS image/application first.
The PL bitstream cannot answer TCP SYN packets.

## 2. Raspberry Pi Backend Configuration

For real hardware, set:

```yaml
device:
  host: <ac920-ps-ip>
```

in `rpi/backend/config/dev.yaml`, or enter the AC920 IP in the frontend host
field before pressing Connect.

The Pi must be able to receive UDP ports:

```text
9001 IQ binary
9002 PSD binary
9003 status JSON
```

Temporarily stop firewalls during bring-up, or explicitly allow these ports.

## 3. AC920 PS Requirements

The PS-side program must:

1. bring up GEM Ethernet and give the AC920 PS a reachable IPv4 address
2. listen on TCP `9000` using newline-delimited JSON
3. accept `hello`, `ping`, `get_status`, `set_rx`, and `stop_all`
4. translate `set_rx` into AXI-Lite CSR writes
5. run AXI DMA S2MM from `m_axis_iq_*`
6. send each 1088 byte DMA packet as one UDP datagram to Pi port `9001`
7. send UDP status JSON to Pi port `9003`

Until these pieces exist, the correct failure mode from the Pi is
`connection refused` or `timed out` on TCP `9000`.

## 4. PL/Data Path Checks

Use ILA or counters to verify:

```text
adc_sample_valid toggles
adc_locked is high
DDC0_CONTROL enables core and ddc0
m_axis_iq_tvalid toggles
m_axis_iq_tready is high from DMA in the s_axi_aclk domain
m_axis_iq_tlast pulses once per packet
DDC0_SAMPLE_COUNT increases
DDC0_OVERFLOW_COUNT stays stable
```

The SC16 payload byte order on the network must be:

```text
int16_le I0
int16_le Q0
int16_le I1
int16_le Q1
```

Because AXI byte lane 0 is `tdata[7:0]`, the PL word for one complex sample must
pack as `{Q[15:0], I[15:0]}`.
