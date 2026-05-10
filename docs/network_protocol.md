# Network Protocol

This document defines the first stable network interface between the AC920
FPGA/PS board and the Raspberry Pi WebSDR backend.

The first implementation target is deliberately simple:

- one AC920 device
- one Raspberry Pi backend as the device owner
- one or two FPGA DDC streams
- UDP binary IQ data
- UDP binary PSD data for the 0.5-108 MHz wideband waterfall
- UDP JSON status data
- TCP JSON control
- TCP raw ADC capture for debug only

Multi-user behavior belongs in the Raspberry Pi Web service. The AC920 network
interface is single-owner in protocol version 1.

## 1. Roles

### AC920

The AC920 side is the device endpoint.

It provides:

- TCP control server
- UDP IQ transmitter
- UDP PSD transmitter
- UDP status transmitter
- optional TCP raw capture server

### Raspberry Pi

The Raspberry Pi backend is the control client and UDP receiver.

It provides:

- TCP control client
- UDP sockets for IQ, PSD, and status
- packet loss detection
- demodulation, audio, waterfall, and Web UI

## 2. Transport Summary

| Purpose | Transport | Default port | Direction | Encoding |
| --- | --- | ---: | --- | --- |
| Control | TCP | 9000 | Raspberry Pi -> AC920 | UTF-8 JSON Lines |
| IQ stream | UDP | 9001 | AC920 -> Raspberry Pi | binary little-endian |
| PSD stream | UDP | 9002 | AC920 -> Raspberry Pi | binary little-endian |
| Status | UDP | 9003 | AC920 -> Raspberry Pi | UTF-8 JSON datagram |
| Raw ADC capture | TCP | 9004 | Raspberry Pi -> AC920 | JSON header + binary payload |

The AC920 listens on TCP port 9000. The Raspberry Pi opens the TCP control
connection and then tells the AC920 which UDP ports it has bound.

The AC920 sends UDP packets to the IP address of the active TCP control peer
unless an explicit destination address is provided in the `hello` command.

Protocol version 1 uses IPv4. IPv6 can be added later without changing packet
payload formats.

## 3. General Rules

### 3.1 Byte Order

All binary UDP fields are little-endian.

Reason: AC920 PS, FPGA-side packers, and Raspberry Pi are all little-endian in
the target system. Using little-endian avoids byte swapping in the high-rate
data path.

JSON messages use UTF-8.

### 3.2 Units

Unless otherwise stated:

- frequency values are integer Hz
- sample rates are integer samples per second
- bandwidth values are integer Hz
- timestamps are ADC sample ticks at 250 MHz
- durations in JSON are milliseconds
- dB fields in JSON are decimal dB values
- dB fields in binary packet headers use signed Q8 dB, meaning `value / 256.0`

### 3.3 UDP Packet Size

Version 1 avoids IP fragmentation.

Default UDP payload size, including protocol header, must be no larger than
1200 bytes.

For IQ packets, the version 1 default is:

- 64 byte IQ header
- 256 complex SC16 samples
- 1024 byte IQ payload
- 1088 byte UDP payload total

For PSD packets, the version 1 default is:

- 72 byte PSD header
- up to 512 `I16_DBFS_Q8` bins
- up to 1024 byte PSD payload
- up to 1096 byte UDP payload total

### 3.4 Single-Owner Rule

Only one TCP control client may own the AC920 at a time.

If a second client connects while one owner is active, the AC920 should reject
the new session with:

```json
{"ok":false,"error":{"code":"busy","message":"device already has an owner"}}
```

The owner is released when the TCP control connection closes or times out.

### 3.5 Fail-Safe Timeout

The Raspberry Pi must send either a command or a `ping` at least every 2 seconds.

If the AC920 receives no valid control message for 10 seconds, it must:

- stop all UDP streams
- disable any armed raw capture
- keep the current front-end state unchanged
- release the control owner

This prevents a crashed Raspberry Pi process from leaving a continuous UDP flood
on the network.

## 4. TCP Control Protocol

### 4.1 Framing

The control channel uses newline-delimited JSON.

Each request or response is one complete JSON object followed by `\n`.

Rules:

- no embedded newline inside a JSON message
- maximum line length: 65536 bytes
- UTF-8 encoding
- unknown request fields must be ignored unless they conflict with known fields
- unknown commands must return `invalid_command`

### 4.2 Request Format

Every request must include:

```json
{
  "request_id": 1,
  "cmd": "ping"
}
```

`request_id` is an unsigned integer chosen by the Raspberry Pi. It is echoed in
the response.

### 4.3 Response Format

Successful response:

```json
{
  "request_id": 1,
  "ok": true
}
```

Error response:

```json
{
  "request_id": 1,
  "ok": false,
  "error": {
    "code": "invalid_field",
    "message": "frequency_hz is out of range"
  }
}
```

If the request cannot be parsed and no `request_id` is available, the AC920
responds with:

```json
{
  "ok": false,
  "error": {
    "code": "invalid_json",
    "message": "request is not valid JSON"
  }
}
```

### 4.4 Error Codes

| Code | Meaning |
| --- | --- |
| `invalid_json` | Message is not valid JSON |
| `unsupported_version` | Protocol version is unsupported |
| `invalid_command` | `cmd` is unknown |
| `invalid_field` | Required field is missing or has the wrong type |
| `out_of_range` | Field is valid but outside supported limits |
| `busy` | Device is owned by another client or resource is unavailable |
| `hardware_fault` | ADC, FPGA, DMA, clock, or front-end fault |
| `timeout` | Command could not complete before its deadline |
| `internal_error` | Unclassified implementation error |

## 5. Control Commands

### 5.1 `hello`

`hello` must be the first command after TCP connection.

Request:

```json
{
  "request_id": 1,
  "cmd": "hello",
  "protocol_version": 1,
  "client_name": "rpi-sdr-backend",
  "udp": {
    "iq_port": 9001,
    "psd_port": 9002,
    "status_port": 9003
  }
}
```

Optional field:

```json
{
  "udp": {
    "destination_ip": "192.168.1.20"
  }
}
```

If `destination_ip` is omitted, the AC920 sends UDP packets to the source IP of
the TCP control connection.

Response:

```json
{
  "request_id": 1,
  "ok": true,
  "protocol_version": 1,
  "device": {
    "name": "AC920-ACFL3432",
    "serial": "unknown",
    "firmware_version": "0.1.0",
    "fpga_build_id": "unknown"
  },
  "limits": {
    "adc_sample_rate_hz": 250000000,
    "min_frequency_hz": 500000,
    "max_frequency_hz": 108000000,
    "max_iq_streams": 2,
    "supported_iq_sample_rates_hz": [125000, 250000, 500000, 1000000],
    "supported_sample_formats": ["SC16_LE"],
    "supported_psd_sources": ["adc0"],
    "supported_psd_output_bins": [4096],
    "supported_psd_fps": [10],
    "supported_psd_sample_formats": ["I16_DBFS_Q8"],
    "max_psd_segments_per_frame": 8,
    "max_psd_bins_per_segment": 512,
    "max_udp_payload_bytes": 1200
  }
}
```

### 5.2 `ping`

Used as heartbeat and latency check.

Request:

```json
{
  "request_id": 2,
  "cmd": "ping",
  "client_time_ms": 123456
}
```

Response:

```json
{
  "request_id": 2,
  "ok": true,
  "client_time_ms": 123456,
  "device_time_ms": 7890
}
```

### 5.3 `get_status`

Returns the same status object used by UDP status packets.

Request:

```json
{
  "request_id": 3,
  "cmd": "get_status"
}
```

Response:

```json
{
  "request_id": 3,
  "ok": true,
  "status": {
    "type": "status",
    "protocol_version": 1,
    "seq": 42,
    "device_time_ms": 1000,
    "adc_sample_rate_hz": 250000000,
    "adc": {
      "channel": 0,
      "peak_dbfs": -14.5,
      "rms_dbfs": -31.2,
      "or_count": 0,
      "clip_count": 0
    },
    "frontend": {
      "attenuator_db": 10,
      "lna": "bypass",
      "filter": "LPF_108M"
    },
    "streams": [],
    "network": {
      "iq_fifo_overflow_count": 0,
      "psd_fifo_overflow_count": 0
    }
  }
}
```

### 5.4 `set_frontend`

Sets RF front-end controls. The AC920 may forward this to GPIO, SPI, or another
board-specific control path.

Request:

```json
{
  "request_id": 4,
  "cmd": "set_frontend",
  "attenuator_db": 10,
  "lna": "bypass",
  "filter": "LPF_108M"
}
```

Allowed values:

- `attenuator_db`: `0`, `10`, `20`, `30` for the first hardware revision
- `lna`: `"on"` or `"bypass"`
- `filter`: `"LPF_108M"` for the first hardware revision

Response:

```json
{
  "request_id": 4,
  "ok": true,
  "applied": {
    "attenuator_db": 10,
    "lna": "bypass",
    "filter": "LPF_108M"
  }
}
```

If the hardware supports a different attenuator step, the AC920 must report the
actual applied value in `applied`.

### 5.5 `set_rx`

Configures and starts or stops one DDC IQ stream.

Request:

```json
{
  "request_id": 5,
  "cmd": "set_rx",
  "stream_id": 0,
  "adc_channel": 0,
  "frequency_hz": 98500000,
  "mode": "WFM",
  "iq_sample_rate_hz": 1000000,
  "bandwidth_hz": 250000,
  "sample_format": "SC16_LE",
  "enable": true
}
```

Rules:

- `stream_id` is zero-based.
- Version 1 stream IDs are `0` and `1` if the FPGA build supports two streams.
- The first bring-up build may support only stream `0`.
- `adc_channel` is `0` for RF1 and `1` for RF2.
- `frequency_hz` is the DDC center frequency.
- User-facing valid range is `500000` to `108000000`.
- FPGA-internal valid range may be wider, but the AC920 should reject values
  outside the user-facing range in version 1.
- `mode` is metadata for the Raspberry Pi and status display. FPGA behavior is
  controlled by `frequency_hz`, `iq_sample_rate_hz`, and `bandwidth_hz`.
- Allowed `mode` values: `"AM"`, `"USB"`, `"LSB"`, `"CW"`, `"NFM"`, `"WFM"`,
  `"IQ"`.
- Allowed `iq_sample_rate_hz` values: `125000`, `250000`, `500000`,
  `1000000`.
- `sample_format` must be `"SC16_LE"` in version 1.

Response:

```json
{
  "request_id": 5,
  "ok": true,
  "applied": {
    "stream_id": 0,
    "adc_channel": 0,
    "frequency_hz": 98500000,
    "mode": "WFM",
    "iq_sample_rate_hz": 1000000,
    "bandwidth_hz": 250000,
    "sample_format": "SC16_LE",
    "decimation": 250,
    "enable": true
  }
}
```

After a successful enabled `set_rx`, the AC920 must:

- reset that stream's IQ packet sequence number to zero
- send the first IQ packet with `DISCONTINUITY` and `CONFIG_CHANGED` flags set

To stop a stream:

```json
{
  "request_id": 6,
  "cmd": "set_rx",
  "stream_id": 0,
  "enable": false
}
```

### 5.6 `stop_all`

Stops all IQ and PSD streams.

Request:

```json
{
  "request_id": 7,
  "cmd": "stop_all"
}
```

Response:

```json
{
  "request_id": 7,
  "ok": true
}
```

### 5.7 `set_psd`

Configures the FPGA-generated PSD stream used by the full-band Web waterfall.
Version 1 fixes the normal wideband mode to `0.5 MHz` through `108 MHz`,
`4096` output bins, and `10 fps`.

An empty Raspberry Pi REST request to `POST /api/psd` maps to the request below.

Request:

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

Rules:

- Version 1 requires `source` to be `"adc0"`.
- Version 1 full-band PSD covers `500000` to `108000000` Hz.
- Version 1 requires `fft_size` to be `16384`, `output_bins` to be `4096`,
  and `fps` to be `10`.
- `sample_format` must be `"I16_DBFS_Q8"` in version 1.
- Unsupported values must return `out_of_range` or be reported exactly in
  `applied` if the implementation clamps to a valid value.
- Enabling or changing PSD resets `frame_seq` to `0`; the first PSD frame must
  set `SDR_PSD_FLAG_CONFIG_CHANGED`.
- `enable=false` stops PSD UDP transmission for `psd_id` and leaves IQ streams
  unchanged.

Response:

```json
{
  "request_id": 8,
  "ok": true,
  "applied": {
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
}
```

To stop PSD:

```json
{
  "request_id": 9,
  "cmd": "set_psd",
  "psd_id": 0,
  "enable": false
}
```

## 6. UDP IQ Stream

### 6.1 Packet Header

Each IQ UDP datagram contains one 64 byte header followed by interleaved SC16 IQ
samples.

Header C definition:

```c
#include <stdint.h>

#define SDR_IQ_MAGIC 0x51494453u  /* ASCII bytes: 'S' 'D' 'I' 'Q' */
#define SDR_PROTOCOL_VERSION 1u

enum SdrFrameType {
    SDR_FRAME_IQ = 1
};

enum SdrSampleFormat {
    SDR_SAMPLE_SC16_LE = 1
};

enum SdrIqFlags {
    SDR_IQ_FLAG_ADC_OR         = 1u << 0,
    SDR_IQ_FLAG_FIFO_OVERFLOW  = 1u << 1,
    SDR_IQ_FLAG_DISCONTINUITY  = 1u << 2,
    SDR_IQ_FLAG_CONFIG_CHANGED = 1u << 3
};

#pragma pack(push, 1)
typedef struct {
    uint32_t magic;              /* SDR_IQ_MAGIC */
    uint16_t version;            /* 1 */
    uint16_t header_len;         /* 64 */

    uint16_t frame_type;         /* SDR_FRAME_IQ */
    uint16_t stream_id;

    uint32_t seq;                /* per-stream packet sequence */
    uint64_t adc_timestamp;      /* first IQ sample, in 250 MHz ADC ticks */

    uint64_t frequency_hz;       /* DDC center frequency */
    uint32_t iq_sample_rate_hz;
    uint32_t bandwidth_hz;

    uint16_t sample_format;      /* SDR_SAMPLE_SC16_LE */
    uint16_t sample_count;       /* complex samples in payload */

    uint16_t flags;              /* SdrIqFlags */
    int16_t  gain_db_q8;         /* digital gain after DDC filter, dB * 256 */

    uint32_t decimation;         /* 250e6 / iq_sample_rate_hz */
    uint32_t payload_bytes;      /* sample_count * 4 for SC16 */

    uint64_t reserved0;          /* must be zero */
} SdrIqHeader;
#pragma pack(pop)
```

Header size must be exactly 64 bytes.

### 6.2 IQ Payload

For `SC16_LE`, payload is:

```text
int16_le I0
int16_le Q0
int16_le I1
int16_le Q1
...
```

Each value is signed two's-complement. The FPGA should saturate DDC output to
the int16 range.

Flag meanings:

- `SDR_IQ_FLAG_ADC_OR`: ADC over-range was observed during this packet interval.
- `SDR_IQ_FLAG_FIFO_OVERFLOW`: an IQ stream FIFO overflow occurred and samples
  were dropped.
- `SDR_IQ_FLAG_DISCONTINUITY`: packet sequence or timestamp continuity is not
  guaranteed across this packet boundary.
- `SDR_IQ_FLAG_CONFIG_CHANGED`: this is the first packet after stream
  configuration changed.

DDC output saturation should increment `clip_count` in status.

### 6.3 Sequence and Timestamp Rules

`seq`:

- increments by 1 per packet per stream
- wraps modulo `2^32`
- resets to 0 when a stream is enabled or reconfigured

`adc_timestamp`:

- is the ADC tick corresponding to the first IQ sample in the packet
- uses the 250 MHz ADC sample clock domain
- increments by `decimation * sample_count` between normal consecutive packets
- wraps modulo `2^64`

The Raspberry Pi must treat a sequence gap as packet loss and insert an audio
or DSP discontinuity as needed.

### 6.4 Default IQ Packetization

Version 1 default:

| IQ rate | Decimation | Samples per packet | Packets per second | UDP payload bytes |
| ---: | ---: | ---: | ---: | ---: |
| 125000 | 2000 | 256 | 488.28125 | 1088 |
| 250000 | 1000 | 256 | 976.5625 | 1088 |
| 500000 | 500 | 256 | 1953.125 | 1088 |
| 1000000 | 250 | 256 | 3906.25 | 1088 |

The FPGA/PS may use a smaller `sample_count` if required, but must not exceed
the negotiated `max_udp_payload_bytes`.

## 7. UDP PSD Stream

PSD is the formal interface for the full-band Web waterfall. Local Raspberry Pi
FFT from IQ packets remains available as `local_spectrum`, but it is not a
replacement for the `0.5-108 MHz` waterfall.

Version 1 fixed full-band PSD packetization:

| Field | Value |
| --- | ---: |
| Frequency span | `500000-108000000 Hz` |
| FFT size | `16384` |
| Output bins | `4096` |
| Frame rate | `10 fps` |
| Bin spacing | `26245.1171875 Hz` |
| Segments per frame | `8` |
| Bins per segment | `512` |
| PSD payload per segment | `1024 bytes` |
| UDP payload per segment | `1096 bytes` |

### 7.1 Packet Header

Each PSD frame may be split across multiple UDP datagrams. Each datagram carries
a 72 byte header and one segment of bins.

Header C definition:

```c
#include <stdint.h>

#define SDR_PSD_MAGIC 0x53504453u  /* ASCII bytes: 'S' 'D' 'P' 'S' */

enum SdrPsdFrameType {
    SDR_FRAME_PSD = 2
};

enum SdrPsdSampleFormat {
    SDR_PSD_I16_DBFS_Q8 = 1
};

enum SdrPsdFlags {
    SDR_PSD_FLAG_DISCONTINUITY  = 1u << 0,
    SDR_PSD_FLAG_CONFIG_CHANGED = 1u << 1,
    SDR_PSD_FLAG_OVERFLOW       = 1u << 2
};

#pragma pack(push, 1)
typedef struct {
    uint32_t magic;              /* SDR_PSD_MAGIC */
    uint16_t version;            /* 1 */
    uint16_t header_len;         /* 72 */

    uint16_t frame_type;         /* SDR_FRAME_PSD */
    uint16_t psd_id;

    uint32_t frame_seq;          /* increments once per complete PSD frame */
    uint64_t adc_timestamp;      /* timestamp of PSD analysis window */

    uint64_t start_frequency_hz; /* frequency of bin 0 */
    uint64_t bin_spacing_millihz;/* bin spacing in 0.001 Hz */

    uint32_t fft_size;

    uint16_t total_bins;         /* bins in complete PSD frame */
    uint16_t segment_index;      /* zero-based */
    uint16_t segment_count;
    uint16_t bin_start;          /* first bin index carried by this segment */
    uint16_t bin_count;          /* bins carried by this segment */
    uint16_t sample_format;      /* SDR_PSD_I16_DBFS_Q8 */
    uint16_t flags;              /* SdrPsdFlags */
    uint16_t averaging_count;    /* FFT averages included */

    uint32_t payload_bytes;      /* bin_count * 2 for I16_DBFS_Q8 */

    uint64_t reserved0;          /* must be zero */
} SdrPsdHeader;
#pragma pack(pop)
```

Header size must be exactly 72 bytes.

### 7.2 PSD Payload

For `I16_DBFS_Q8`, each bin is:

```text
int16_le power_dbfs_q8
```

Convert to dBFS:

```text
power_dbfs = power_dbfs_q8 / 256.0
```

Frequency for bin `i` in a segment:

```text
frequency_hz =
    start_frequency_hz +
    (bin_start + i) * bin_spacing_millihz / 1000.0
```

For the fixed full-band mode, receivers should use the configured start/stop
range for UI scaling and accept the small millihertz rounding error in
`bin_spacing_millihz`.

### 7.3 PSD Reassembly

The Raspberry Pi groups PSD segments by:

- `psd_id`
- `frame_seq`

A complete PSD frame is available when all segment indices from `0` to
`segment_count - 1` have arrived.

If any segment is missing by the time a newer `frame_seq` arrives, the Raspberry
Pi should drop the incomplete frame.

Segment rules:

- every segment in a frame has the same `psd_id`, `frame_seq`, `adc_timestamp`,
  `start_frequency_hz`, `bin_spacing_millihz`, `fft_size`, `total_bins`,
  `segment_count`, `sample_format`, and `flags`
- `segment_index` runs from `0` to `7`
- `segment_count` is `8`
- `bin_start` is `segment_index * 512`
- `bin_count` is `512`
- `payload_bytes` is `1024`
- segments may arrive out of order
- receivers must ignore duplicate segments after storing the newest copy

### 7.4 PSD Frame Flags

- `SDR_PSD_FLAG_DISCONTINUITY`: frame continuity is not guaranteed across this
  frame boundary.
- `SDR_PSD_FLAG_CONFIG_CHANGED`: this is the first frame after PSD
  configuration changed.
- `SDR_PSD_FLAG_OVERFLOW`: FPGA or PS dropped at least one PSD frame before this
  frame.

### 7.5 Raspberry Pi WebSocket Mapping

After reassembly, the Raspberry Pi publishes full-band PSD on `/ws/spectrum`:

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

Local FFT from the selected DDC stream uses the same WebSocket but a different
message type:

```json
{
  "type": "local_spectrum",
  "center_frequency_hz": 98500000,
  "sample_rate_hz": 1000000,
  "bin_spacing_hz": 488.28125,
  "bins_dbfs": [-80.2, -79.9],
  "flags": 0
}
```

## 8. UDP Status Stream

Status is one UTF-8 JSON object per UDP datagram.

Default send rate:

- 5 Hz while any stream is active
- 1 Hz while idle

The status datagram should stay below 1200 bytes.

Example:

```json
{
  "type": "status",
  "protocol_version": 1,
  "seq": 123,
  "device_time_ms": 100000,
  "adc_sample_rate_hz": 250000000,
  "adc": {
    "channel": 0,
    "peak_dbfs": -14.5,
    "rms_dbfs": -31.2,
    "or_count": 0,
    "clip_count": 0
  },
  "frontend": {
    "attenuator_db": 10,
    "lna": "bypass",
    "filter": "LPF_108M"
  },
  "streams": [
    {
      "stream_id": 0,
      "adc_channel": 0,
      "enabled": true,
      "frequency_hz": 98500000,
      "mode": "WFM",
      "iq_sample_rate_hz": 1000000,
      "bandwidth_hz": 250000,
      "sample_format": "SC16_LE",
      "seq": 4567,
      "fifo_overflow_count": 0
    }
  ],
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
  ],
  "network": {
    "iq_packets_sent": 4568,
    "psd_packets_sent": 0,
    "status_packets_sent": 123,
    "iq_fifo_overflow_count": 0,
    "psd_fifo_overflow_count": 0
  }
}
```

Counters are monotonically increasing since AC920 boot unless otherwise stated.

## 9. Raw ADC Capture TCP Interface

Raw capture is for short debug captures only. It is not a streaming interface.

The AC920 listens on TCP port 9004.

### 9.1 Request

The Raspberry Pi connects to TCP 9004 and sends one JSON line:

```json
{
  "request_id": 1,
  "cmd": "capture_raw",
  "adc_channel": 0,
  "sample_count": 65536,
  "sample_format": "S16_LE"
}
```

Rules:

- `sample_count` maximum is 1048576 in version 1.
- `sample_format` must be `"S16_LE"`.
- Samples are sign-extended ADC values in signed int16 format.
- Raw capture should not run while high-rate IQ or PSD streams are active unless
  the FPGA build explicitly supports it.

### 9.2 Response

If accepted, AC920 sends one JSON line:

```json
{
  "request_id": 1,
  "ok": true,
  "adc_sample_rate_hz": 250000000,
  "adc_channel": 0,
  "sample_count": 65536,
  "sample_format": "S16_LE",
  "payload_bytes": 131072
}
```

Then it sends exactly `payload_bytes` of binary payload and closes the capture
connection.

If rejected, AC920 sends an error response and closes the connection:

```json
{
  "request_id": 1,
  "ok": false,
  "error": {
    "code": "busy",
    "message": "raw capture is unavailable while IQ stream is active"
  }
}
```

## 10. Recommended Startup Sequence

1. Raspberry Pi backend starts.
2. Raspberry Pi binds UDP ports 9001, 9002, and 9003.
3. Raspberry Pi connects to AC920 TCP 9000.
4. Raspberry Pi sends `hello`.
5. AC920 accepts ownership and returns device limits.
6. Raspberry Pi sends `get_status`.
7. Raspberry Pi sends `set_frontend`.
8. Raspberry Pi sends `set_rx`.
9. AC920 starts UDP IQ and status packets.
10. Raspberry Pi sends `ping` every 2 seconds while connected.

## 11. Recommended Shutdown Sequence

1. Raspberry Pi sends `stop_all`.
2. AC920 stops IQ and PSD UDP streams.
3. Raspberry Pi closes TCP control connection.
4. AC920 releases the owner.

If the TCP connection drops unexpectedly, AC920 must apply the fail-safe timeout
rules in section 3.5.

## 12. Version 1 Fixed Decisions

These choices are considered fixed for the first implementation:

- TCP control is JSON Lines, not binary RPC.
- UDP IQ is binary SC16 little-endian.
- UDP status is JSON.
- AC920 supports one active owner.
- UDP destination is learned from `hello`.
- IQ packets default to 256 complex samples.
- ADC timestamp unit is 250 MHz ADC ticks.
- UDP PSD is the full-band waterfall interface.
- PSD version 1 is `adc0`, `500000-108000000 Hz`, `16384` point FFT,
  `4096` bins, `10 fps`, `I16_DBFS_Q8`, split into `8` segments per frame.
- Raw ADC data is short capture only, never continuous streaming.

## 13. Open Items for Later Versions

The following are intentionally not solved in version 1:

- authentication or encryption
- device discovery
- multiple AC920 devices
- multiple independent network owners
- Opus/WebRTC browser audio transport
- compressed 8-bit PSD payloads
- jumbo-frame IQ packet mode
- remote firmware or bitstream update
