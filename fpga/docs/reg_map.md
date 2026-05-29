# Register Map

AXI-Lite 地址为 byte address，数据宽度 32 bit。

| 地址 | 读写 | 名称 | 说明 |
|---:|---|---|---|
| `0x000` | R | `CORE_ID` | `0x53445231`，`SDR1` |
| `0x004` | R | `CORE_VERSION` | `0x00010000` |
| `0x008` | R/W | `CONTROL` | bit0 core enable, bit1 soft reset pulse, bit2 ADC offset-binary |
| `0x00c` | R | `ADC_STATUS` | bit0 enable, bit1 adc_locked, bit2 adc_or |
| `0x010` | R | `ADC_PEAK` | selected ADC channel peak absolute sample |
| `0x014` | R | `ADC_RMS` | selected ADC channel mean-square sample power |
| `0x018` | R | `OR_COUNT` | CM3432 OR rising edge count；当前 AC920 demo pinout 未接 OR，顶层置 0 |
| `0x01c` | R | `CLIP_COUNT` | ADC clip + DDC SC16 saturation count |
| `0x020` | W | `CLEAR_COUNTS` | write bit0=1 to clear OR/clip counts |
| `0x100` | R/W | `DDC0_CONTROL` | bit0 stream enable, bit1 adc_channel |
| `0x104` | R/W | `DDC0_FREQ_WORD` | 32-bit NCO frequency word |
| `0x108` | R/W | `DDC0_DECIM` | CIC decimation rate |
| `0x10c` | R/W | `DDC0_GAIN` | output arithmetic right shift |
| `0x110` | R | `DDC0_SAMPLES` | accepted IQ sample count before packetizer |
| `0x114` | R | `DDC0_OVERFLOW` | dropped IQ sample count before packetizer |
| `0x118` | R/W | `DDC0_FREQ_HZ_L` | packet header `frequency_hz[31:0]` |
| `0x11c` | R/W | `DDC0_FREQ_HZ_H` | packet header `frequency_hz[63:32]` |
| `0x120` | R/W | `DDC0_IQ_RATE` | packet header `iq_sample_rate_hz` |
| `0x124` | R/W | `DDC0_BANDWIDTH` | packet header `bandwidth_hz` |
| `0x128` | R/W | `DDC0_GAIN_DB` | packet header signed `gain_db_q8[15:0]` |

推荐 PS 初始化顺序：

```text
write CONTROL          = 0x00000002
write DDC0_FREQ_HZ_L   = frequency_hz
write DDC0_FREQ_HZ_H   = 0
write DDC0_FREQ_WORD   = round(frequency_hz / 250e6 * 2^32)
write DDC0_IQ_RATE     = iq_sample_rate_hz
write DDC0_DECIM       = 250e6 / iq_sample_rate_hz
write DDC0_BANDWIDTH   = bandwidth_hz
write DDC0_GAIN        = gain_shift
write DDC0_GAIN_DB     = 0
write DDC0_CONTROL     = {adc_channel, enable}
write CONTROL          = 1
```

每次写 `CONTROL` 或 `DDC0_*` 配置寄存器都会触发 packetizer：

```text
seq reset to 0
first packet flags include DISCONTINUITY and CONFIG_CHANGED
```
