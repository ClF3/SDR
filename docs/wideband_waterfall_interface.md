# Wideband Waterfall Interface

This document is the FPGA/PS-to-Raspberry Pi contract for the full-band
`0.5-108 MHz` waterfall. It defines only the interface. It does not prescribe
or implement FPGA RTL.

## Target

| Item | Version 1 value |
| --- | ---: |
| Source | `adc0` |
| Display span | `500000-108000000 Hz` |
| FFT size | `16384` |
| Output bins | `4096` |
| Output rate | `10 fps` |
| Sample format | `I16_DBFS_Q8` |
| UDP port | `9002` |
| Header | `SdrPsdHeader`, 72 bytes |
| Segments per frame | `8` |
| Bins per segment | `512` |
| Payload per segment | `1024 bytes` |

The bin spacing used by the Web UI is:

```text
bin_spacing_hz = (108000000 - 500000) / 4096
               = 26245.1171875 Hz
```

## Control

The Raspberry Pi enables PSD with TCP JSON Lines command `set_psd`:

```json
{
  "request_id": 8,
  "cmd": "set_psd",
  "psd_id": 0,
  "source": "adc0",
  "enable": true,
  "start_frequency_hz": 500000,
  "stop_frequency_hz": 108000000,
  "fft_size": 16384,
  "output_bins": 4096,
  "fps": 10,
  "sample_format": "I16_DBFS_Q8"
}
```

The AC920 response must echo the applied configuration. Unsupported settings
must either be rejected with `out_of_range` or returned with the actual clamped
value in `applied`.

To stop the full-band waterfall:

```json
{
  "request_id": 9,
  "cmd": "set_psd",
  "psd_id": 0,
  "enable": false
}
```

`enable=false` stops PSD UDP packets only. It must not stop IQ streams.
`stop_all` stops both IQ and PSD streams.

## UDP Frame Layout

Each PSD frame contains `4096` bins and is split into `8` UDP datagrams:

| Segment | `segment_index` | `bin_start` | `bin_count` |
| ---: | ---: | ---: | ---: |
| 0 | 0 | 0 | 512 |
| 1 | 1 | 512 | 512 |
| 2 | 2 | 1024 | 512 |
| 3 | 3 | 1536 | 512 |
| 4 | 4 | 2048 | 512 |
| 5 | 5 | 2560 | 512 |
| 6 | 6 | 3072 | 512 |
| 7 | 7 | 3584 | 512 |

Every datagram is:

```text
72-byte SdrPsdHeader
1024-byte int16_le power_dbfs_q8 payload
```

The full UDP payload is `1096` bytes and must stay below the protocol maximum
of `1200` bytes.

## Frequency Mapping

For bin index `b` in the complete reassembled frame:

```text
frequency_hz = 500000 + b * 26245.1171875
```

For a bin inside one segment:

```text
absolute_bin = bin_start + i
frequency_hz = start_frequency_hz
             + absolute_bin * bin_spacing_millihz / 1000.0
```

The binary header stores `bin_spacing_millihz` as an integer, so there can be
sub-Hz rounding in the header value. The Raspberry Pi Web UI uses the configured
`start_frequency_hz` and `stop_frequency_hz` for cursor mapping.

## Sequence Rules

- `frame_seq` increments once per complete PSD frame and wraps modulo `2^32`.
- Enabling or changing PSD resets `frame_seq` to `0`.
- The first frame after enable/reconfigure sets `SDR_PSD_FLAG_CONFIG_CHANGED`.
- If a PSD FIFO overflow or dropped frame occurs before a frame is transmitted,
  set `SDR_PSD_FLAG_OVERFLOW` on the next transmitted frame.
- Segments within one frame may be sent in order or out of order.
- The Raspberry Pi reassembles by `(psd_id, frame_seq)`.
- If a newer `frame_seq` arrives before all segments of an older frame arrived,
  the Raspberry Pi drops the older frame and increments missing segment counts.

## Status Counters

UDP status JSON must include PSD state:

```json
{
  "psd": [
    {
      "psd_id": 0,
      "enabled": true,
      "source": "adc0",
      "start_frequency_hz": 500000,
      "stop_frequency_hz": 108000000,
      "fft_size": 16384,
      "output_bins": 4096,
      "fps": 10,
      "frame_seq": 123,
      "dropped_frame_count": 0,
      "missing_segment_count": 0,
      "overflow_count": 0
    }
  ]
}
```

`network.psd_packets_sent` and `network.psd_fifo_overflow_count` should also be
reported when available.

## Raspberry Pi Output

After receiving all 8 segments, the backend publishes `/ws/spectrum`:

```json
{
  "type": "wideband_psd",
  "psd_id": 0,
  "frame_seq": 123,
  "start_frequency_hz": 500000,
  "stop_frequency_hz": 108000000,
  "bin_spacing_hz": 26245.1171875,
  "bins_dbfs": [-92.5, -91.8],
  "flags": 0,
  "dropped_frame_count": 0,
  "missing_segment_count": 0
}
```

The browser maps mouse or touch x-coordinate to frequency as:

```text
frequency_hz = start + x / canvas_width * (stop - start)
```

Dragging only moves the cursor. Releasing the pointer sends one `/api/rx`
request to tune the current DDC stream.

## Acceptance

An FPGA/PS implementation is compatible when:

- `hello.limits` advertises `adc0`, `4096` bins, `10 fps`, and
  `I16_DBFS_Q8`.
- `set_psd` starts UDP `9002` output within one second.
- Every complete frame contains 8 segments and exactly 4096 bins.
- The first frame after enable has `CONFIG_CHANGED`.
- The Raspberry Pi can reassemble frames for at least 10 minutes with no
  unexpected sequence resets.
- Simulated or injected peaks appear at the expected Web UI frequency positions.
- `enable=false` stops PSD without interrupting active IQ/audio streams.
