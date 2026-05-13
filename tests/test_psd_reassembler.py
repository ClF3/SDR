from __future__ import annotations

import unittest

from common.protocol import SdrPsdHeader
from rpi.backend.sdr_backend.psd import PsdReassembler


TOTAL_BINS = 4096
BINS_PER_SEGMENT = 512
SEGMENTS = 8


def make_segment(frame_seq: int, segment_index: int) -> tuple[SdrPsdHeader, bytes]:
    bin_start = segment_index * BINS_PER_SEGMENT
    values = [-100 * 256 + index for index in range(bin_start, bin_start + BINS_PER_SEGMENT)]
    payload = b"".join(value.to_bytes(2, "little", signed=True) for value in values)
    return (
        SdrPsdHeader(
            psd_id=0,
            frame_seq=frame_seq,
            adc_timestamp=frame_seq * 1_000_000,
            start_frequency_hz=500_000,
            bin_spacing_millihz=26_245_117,
            fft_size=16_384,
            total_bins=TOTAL_BINS,
            segment_index=segment_index,
            segment_count=SEGMENTS,
            bin_start=bin_start,
            bin_count=BINS_PER_SEGMENT,
            payload_bytes=len(payload),
            stop_frequency_hz=108_000_000,
        ),
        payload,
    )


class PsdReassemblerTests(unittest.TestCase):
    def test_reassembles_4096_bins_from_8_segments(self) -> None:
        reassembler = PsdReassembler()
        frame = None
        for segment_index in range(SEGMENTS):
            header, payload = make_segment(12, segment_index)
            frame = reassembler.ingest(header, payload)

        self.assertIsNotNone(frame)
        assert frame is not None
        self.assertEqual(frame["type"], "wideband_psd")
        self.assertEqual(frame["frame_seq"], 12)
        self.assertEqual(frame["start_frequency_hz"], 500_000)
        self.assertEqual(frame["stop_frequency_hz"], 108_000_000)
        self.assertAlmostEqual(frame["bin_spacing_hz"], 26_245.1171875)
        self.assertEqual(len(frame["bins_dbfs"]), TOTAL_BINS)
        self.assertEqual(frame["bins_dbfs"][0], -100.0)

    def test_out_of_order_segments_reassemble(self) -> None:
        reassembler = PsdReassembler()
        frame = None
        for segment_index in reversed(range(SEGMENTS)):
            header, payload = make_segment(13, segment_index)
            frame = reassembler.ingest(header, payload)

        self.assertIsNotNone(frame)
        assert frame is not None
        self.assertEqual(frame["frame_seq"], 13)
        self.assertEqual(len(frame["bins_dbfs"]), TOTAL_BINS)

    def test_missing_segment_is_counted_when_newer_frame_arrives(self) -> None:
        reassembler = PsdReassembler()
        for segment_index in range(SEGMENTS - 1):
            header, payload = make_segment(14, segment_index)
            self.assertIsNone(reassembler.ingest(header, payload))

        header, payload = make_segment(15, 0)
        self.assertIsNone(reassembler.ingest(header, payload))
        self.assertEqual(reassembler.stats.dropped_frame_count, 1)
        self.assertEqual(reassembler.stats.missing_segment_count, 1)

    def test_q8_payload_is_converted_to_float_dbfs(self) -> None:
        reassembler = PsdReassembler()
        header = SdrPsdHeader(
            frame_seq=16,
            start_frequency_hz=500_000,
            bin_spacing_millihz=26_245_117,
            fft_size=16_384,
            total_bins=1,
            segment_index=0,
            segment_count=1,
            bin_start=0,
            bin_count=1,
            payload_bytes=2,
            stop_frequency_hz=108_000_000,
        )
        payload = int(-92.5 * 256).to_bytes(2, "little", signed=True)
        frame = reassembler.ingest(header, payload)

        self.assertIsNotNone(frame)
        assert frame is not None
        self.assertEqual(frame["bins_dbfs"], [-92.5])

    def test_uses_header_stop_frequency_for_zoom_roi(self) -> None:
        reassembler = PsdReassembler()
        header = SdrPsdHeader(
            frame_seq=17,
            start_frequency_hz=98_000_000,
            bin_spacing_millihz=244_141,
            fft_size=16_384,
            total_bins=4096,
            segment_index=0,
            segment_count=1,
            bin_start=0,
            bin_count=1,
            payload_bytes=2,
            stop_frequency_hz=99_000_000,
        )
        frame = reassembler.ingest(header, int(-80 * 256).to_bytes(2, "little", signed=True))

        self.assertIsNotNone(frame)
        assert frame is not None
        self.assertEqual(frame["start_frequency_hz"], 98_000_000)
        self.assertEqual(frame["stop_frequency_hz"], 99_000_000)
        self.assertAlmostEqual(frame["bin_spacing_hz"], 244.140625)


if __name__ == "__main__":
    unittest.main()
