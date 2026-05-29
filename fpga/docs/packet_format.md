# IQ Packet Format

FPGA 输出到 AXI DMA 的每个 TLAST packet 是一个完整的 UDP IQ payload：

```text
64 byte SdrIqHeader
1024 byte SC16 IQ payload
1088 byte total
```

32-bit AXI word 顺序：

| word | struct fields | value |
|---:|---|---|
| 0 | `magic` | `0x51494453`，little-endian bytes `S D I Q` |
| 1 | `version`, `header_len` | `0x00400001` |
| 2 | `frame_type`, `stream_id` | `{stream_id, 16'd1}` |
| 3 | `seq` | packet sequence |
| 4 | `adc_timestamp[31:0]` | timestamp low |
| 5 | `adc_timestamp[63:32]` | timestamp high |
| 6 | `frequency_hz[31:0]` | frequency low |
| 7 | `frequency_hz[63:32]` | frequency high |
| 8 | `iq_sample_rate_hz` | from CSR |
| 9 | `bandwidth_hz` | from CSR |
| 10 | `sample_format`, `sample_count` | `{16'd256, 16'd1}` |
| 11 | `flags`, `gain_db_q8` | `{gain_db_q8, flags}` |
| 12 | `decimation` | from CSR |
| 13 | `payload_bytes` | `1024` |
| 14 | `reserved0[31:0]` | `0` |
| 15 | `reserved0[63:32]` | `0` |

Payload word:

```text
m_axis_iq_tdata[15:0]  = I signed 16-bit
m_axis_iq_tdata[31:16] = Q signed 16-bit
```

AXI byte lane 0 is `tdata[7:0]`, so this produces network payload bytes:

```text
int16_le I0, int16_le Q0, int16_le I1, int16_le Q1, ...
```

`m_axis_iq_tkeep` is always `4'hf`; `m_axis_iq_tlast` is asserted on the final
IQ word of each packet.

Implemented flags:

```text
bit0 ADC_OR
bit1 FIFO_OVERFLOW
bit2 DISCONTINUITY
bit3 CONFIG_CHANGED
```

The first packet after stream enable or reconfiguration sets bits 2 and 3.
