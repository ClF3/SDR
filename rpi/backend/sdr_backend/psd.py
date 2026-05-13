"""Wideband PSD segment reassembly."""

from __future__ import annotations

from dataclasses import dataclass, field

from common.protocol import SdrPsdHeader


@dataclass(slots=True)
class PsdFrameBuffer:
    header: SdrPsdHeader
    segments: dict[int, bytes] = field(default_factory=dict)


@dataclass(slots=True)
class PsdStats:
    complete_frames: int = 0
    dropped_frame_count: int = 0
    missing_segment_count: int = 0
    last_frame_seq: int | None = None


class PsdReassembler:
    def __init__(self) -> None:
        self._frames: dict[tuple[int, int], PsdFrameBuffer] = {}
        self.stats = PsdStats()

    def reset(self) -> None:
        self._frames.clear()
        self.stats = PsdStats()

    def ingest(self, header: SdrPsdHeader, payload: bytes) -> dict | None:
        self._drop_older_frames(header.psd_id, header.frame_seq)
        key = (header.psd_id, header.frame_seq)
        frame = self._frames.setdefault(key, PsdFrameBuffer(header=header))
        frame.segments[header.segment_index] = payload

        if len(frame.segments) < header.segment_count:
            return None

        ordered = [frame.segments.get(index) for index in range(header.segment_count)]
        if any(segment is None for segment in ordered):
            return None

        del self._frames[key]
        self.stats.complete_frames += 1
        self.stats.last_frame_seq = header.frame_seq
        bins_q8 = self._decode_bins(b"".join(segment for segment in ordered if segment is not None))
        start_frequency_hz, stop_frequency_hz, bin_spacing_hz = self._frequency_bounds(header)
        return {
            "type": "wideband_psd",
            "psd_id": header.psd_id,
            "frame_seq": header.frame_seq,
            "start_frequency_hz": start_frequency_hz,
            "stop_frequency_hz": stop_frequency_hz,
            "bin_spacing_hz": bin_spacing_hz,
            "fft_size": header.fft_size,
            "total_bins": header.total_bins,
            "bins_dbfs": bins_q8[: header.total_bins],
            "flags": header.flags,
            "dropped_frame_count": self.stats.dropped_frame_count,
            "missing_segment_count": self.stats.missing_segment_count,
        }

    def _drop_older_frames(self, psd_id: int, frame_seq: int) -> None:
        stale_keys = [
            key for key in self._frames
            if key[0] == psd_id and self._seq_less(key[1], frame_seq)
        ]
        for key in stale_keys:
            frame = self._frames.pop(key)
            expected = frame.header.segment_count
            missing = max(0, expected - len(frame.segments))
            self.stats.dropped_frame_count += 1
            self.stats.missing_segment_count += missing

    def _seq_less(self, left: int, right: int) -> bool:
        return left != right and ((right - left) & 0xFFFFFFFF) < 0x80000000

    def _decode_bins(self, payload: bytes) -> list[float]:
        values = []
        for index in range(0, len(payload) - 1, 2):
            q8 = int.from_bytes(payload[index:index + 2], "little", signed=True)
            values.append(round(q8 / 256.0, 2))
        return values

    def _frequency_bounds(self, header: SdrPsdHeader) -> tuple[int, int | float, float]:
        if header.stop_frequency_hz > header.start_frequency_hz:
            stop_frequency_hz = header.stop_frequency_hz
            return (
                header.start_frequency_hz,
                stop_frequency_hz,
                (stop_frequency_hz - header.start_frequency_hz) / header.total_bins,
            )
        bin_spacing_hz = header.bin_spacing_millihz / 1000.0
        return (
            header.start_frequency_hz,
            header.start_frequency_hz + header.total_bins * bin_spacing_hz,
            bin_spacing_hz,
        )
