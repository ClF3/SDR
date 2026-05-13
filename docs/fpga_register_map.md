# FPGA Register Map

This register map defines the PS-to-PL control/status contract needed for the
Raspberry Pi wideband waterfall interface. It is intentionally interface-only:
no RTL implementation, Vivado project, or FFT architecture is specified here.

All registers are little-endian 32-bit words. Offsets are relative to the PSD
control block base address chosen by the AC920 PS integration.

## PSD Control Registers

| Offset | Name | R/W | Description |
| ---: | --- | --- | --- |
| `0x0000` | `PSD_CONTROL` | R/W | bit0 `enable`, bit1 `reset`, bit2 `irq_enable` |
| `0x0004` | `PSD_STATUS` | R | bit0 `running`, bit1 `frame_ready`, bit2 `overflow`, bit3 `config_changed_pending` |
| `0x0008` | `PSD_SOURCE` | R/W | `0=adc0`; other values reserved for v2 |
| `0x000C` | `PSD_ID` | R/W | PSD stream id, v1 default `0` |
| `0x0010` | `PSD_START_HZ_LO` | R/W | low 32 bits of start frequency |
| `0x0014` | `PSD_START_HZ_HI` | R/W | high 32 bits of start frequency |
| `0x0018` | `PSD_STOP_HZ_LO` | R/W | low 32 bits of stop frequency |
| `0x001C` | `PSD_STOP_HZ_HI` | R/W | high 32 bits of stop frequency |
| `0x0020` | `PSD_FFT_SIZE` | R/W | v1 fixed `16384` |
| `0x0024` | `PSD_OUTPUT_BINS` | R/W | v1 fixed `4096` |
| `0x0028` | `PSD_FPS` | R/W | v1 fixed `10` |
| `0x002C` | `PSD_FORMAT` | R/W | `1=I16_DBFS_Q8` |
| `0x0030` | `PSD_AVERAGING_COUNT` | R/W | FFT averages included in one frame |
| `0x0034` | `PSD_SEGMENT_BINS` | R/W | v1 fixed `512` |
| `0x0038` | `PSD_FRAME_SEQ` | R | next frame sequence number |
| `0x003C` | `PSD_DROPPED_FRAMES` | R | PL/PS dropped full PSD frames |
| `0x0040` | `PSD_MISSING_SEGMENTS` | R | reserved for PS packetizer diagnostics |
| `0x0044` | `PSD_OVERFLOW_COUNT` | R | PSD FIFO or DMA overflow counter |
| `0x0048` | `PSD_LAST_ADC_TS_LO` | R | low 32 bits of last PSD ADC timestamp |
| `0x004C` | `PSD_LAST_ADC_TS_HI` | R | high 32 bits of last PSD ADC timestamp |

## Version 1 Defaults

When AC920 receives `set_psd`, PS programs the requested range. The default
full-band request uses:

| Register | Value |
| --- | ---: |
| `PSD_SOURCE` | `0` |
| `PSD_ID` | `0` |
| `PSD_START_HZ` | `500000` |
| `PSD_STOP_HZ` | `108000000` |
| `PSD_FFT_SIZE` | `16384` |
| `PSD_OUTPUT_BINS` | `4096` |
| `PSD_FPS` | `10` |
| `PSD_FORMAT` | `1` |
| `PSD_SEGMENT_BINS` | `512` |

The derived bin spacing is:

```text
bin_spacing_hz = (PSD_STOP_HZ - PSD_START_HZ) / PSD_OUTPUT_BINS
               = 26245.1171875 Hz
```

For zoom ROI, PS writes the requested `PSD_START_HZ` and `PSD_STOP_HZ` while
keeping version 1 `PSD_OUTPUT_BINS = 4096`. For example, `98-99 MHz` gives:

```text
bin_spacing_hz = (99000000 - 98000000) / 4096
               = 244.140625 Hz
```

## Control Behavior

`set_psd enable=true`:

1. PS writes all configuration registers.
2. PS writes `PSD_CONTROL.reset=1`, then clears it after the PL block
   acknowledges reset by clearing `PSD_STATUS.running`.
3. PS writes `PSD_CONTROL.enable=1`.
4. PL resets `PSD_FRAME_SEQ` to `0`.
5. The first frame metadata must have `CONFIG_CHANGED`.

Changing only the PSD range follows the same reset sequence and resets
`PSD_FRAME_SEQ` to `0`.

`set_psd enable=false`:

1. PS clears `PSD_CONTROL.enable`.
2. PL stops producing new PSD segments.
3. IQ/DDC blocks remain untouched.

`stop_all` clears both DDC stream enables and `PSD_CONTROL.enable`.

## PL-to-PS Segment Metadata

The PL block hands each completed PSD segment to PS with this metadata. PS uses
it to populate the 72-byte `SdrPsdHeader` described in
`docs/network_protocol.md`.

```c
typedef struct {
    uint16_t psd_id;
    uint16_t segment_index;
    uint16_t segment_count;
    uint16_t bin_start;
    uint16_t bin_count;
    uint16_t flags;
    uint32_t frame_seq;
    uint64_t adc_timestamp;
    uint64_t start_frequency_hz;
    uint64_t stop_frequency_hz;
    uint64_t bin_spacing_millihz;
    uint32_t fft_size;
    uint16_t total_bins;
    uint16_t averaging_count;
} PsdSegmentMeta;
```

Version 1 segment values:

- `segment_count = 8`
- `bin_count = 512`
- `bin_start = segment_index * 512`
- payload is `512` signed `I16_DBFS_Q8` values

## Status Bits

`PSD_STATUS.overflow` is sticky until PS writes `PSD_CONTROL.reset=1` or a
future explicit clear register is added. When set, PS must increment
`overflow_count` in UDP status and set `SDR_PSD_FLAG_OVERFLOW` on the next
transmitted PSD frame.

`PSD_STATUS.config_changed_pending` is set after configuration/reset and clears
when PS packetizes the first frame with `SDR_PSD_FLAG_CONFIG_CHANGED`.

## Out of Scope

- FFT/window implementation
- averaging algorithm
- log power calibration
- DMA descriptor format
- interrupt topology
- multi-source PSD arbitration
