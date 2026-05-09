"""Runtime state aggregation for API and WebSocket consumers."""

from __future__ import annotations

from dataclasses import dataclass, field
import time
from typing import Any

from common.protocol import (
    SDR_IQ_FLAG_ADC_OR,
    SDR_IQ_FLAG_FIFO_OVERFLOW,
    SdrIqHeader,
)


@dataclass(slots=True)
class StreamStats:
    stream_id: int
    packets: int = 0
    lost_packets: int = 0
    timestamp_gaps: int = 0
    adc_or_count: int = 0
    fifo_overflow_count: int = 0
    last_seq: int | None = None
    last_timestamp: int | None = None
    last_frequency_hz: int = 0
    last_iq_sample_rate_hz: int = 0
    last_bandwidth_hz: int = 0
    last_flags: int = 0


@dataclass(slots=True)
class AppState:
    started_at: float = field(default_factory=time.monotonic)
    connected: bool = False
    device_host: str | None = None
    hello: dict[str, Any] | None = None
    device_status: dict[str, Any] | None = None
    frontend: dict[str, Any] = field(default_factory=dict)
    rx: dict[str, Any] = field(default_factory=dict)
    streams: dict[int, StreamStats] = field(default_factory=dict)
    last_error: str | None = None

    def ingest_iq_header(self, header: SdrIqHeader) -> StreamStats:
        stats = self.streams.setdefault(header.stream_id, StreamStats(header.stream_id))
        if stats.last_seq is not None:
            expected_seq = (stats.last_seq + 1) & 0xFFFFFFFF
            if header.seq != expected_seq:
                stats.lost_packets += (header.seq - expected_seq) & 0xFFFFFFFF
        if stats.last_timestamp is not None:
            expected_ts = (stats.last_timestamp + header.next_timestamp_delta) & 0xFFFFFFFFFFFFFFFF
            if header.adc_timestamp != expected_ts:
                stats.timestamp_gaps += 1
        if header.flags & SDR_IQ_FLAG_ADC_OR:
            stats.adc_or_count += 1
        if header.flags & SDR_IQ_FLAG_FIFO_OVERFLOW:
            stats.fifo_overflow_count += 1
        stats.packets += 1
        stats.last_seq = header.seq
        stats.last_timestamp = header.adc_timestamp
        stats.last_frequency_hz = header.frequency_hz
        stats.last_iq_sample_rate_hz = header.iq_sample_rate_hz
        stats.last_bandwidth_hz = header.bandwidth_hz
        stats.last_flags = header.flags
        return stats

    def snapshot(self) -> dict[str, Any]:
        return {
            "connected": self.connected,
            "device_host": self.device_host,
            "uptime_s": round(time.monotonic() - self.started_at, 3),
            "hello": self.hello,
            "device_status": self.device_status,
            "frontend": self.frontend,
            "rx": self.rx,
            "streams": {
                str(stream_id): {
                    "packets": stats.packets,
                    "lost_packets": stats.lost_packets,
                    "timestamp_gaps": stats.timestamp_gaps,
                    "adc_or_count": stats.adc_or_count,
                    "fifo_overflow_count": stats.fifo_overflow_count,
                    "last_seq": stats.last_seq,
                    "last_timestamp": stats.last_timestamp,
                    "last_frequency_hz": stats.last_frequency_hz,
                    "last_iq_sample_rate_hz": stats.last_iq_sample_rate_hz,
                    "last_bandwidth_hz": stats.last_bandwidth_hz,
                    "last_flags": stats.last_flags,
                }
                for stream_id, stats in sorted(self.streams.items())
            },
            "last_error": self.last_error,
        }

