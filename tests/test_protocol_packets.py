from __future__ import annotations

import unittest

from common.protocol import (
    IQ_HEADER_SIZE,
    PSD_HEADER_SIZE,
    SDR_IQ_FLAG_CONFIG_CHANGED,
    SDR_IQ_FLAG_DISCONTINUITY,
    SdrIqHeader,
    SdrPsdHeader,
)
from common.protocol.packets import PacketError


class PacketProtocolTests(unittest.TestCase):
    def test_iq_header_is_64_bytes_and_round_trips(self) -> None:
        header = SdrIqHeader(
            stream_id=1,
            seq=123,
            adc_timestamp=456,
            frequency_hz=98_500_000,
            iq_sample_rate_hz=1_000_000,
            bandwidth_hz=250_000,
            sample_count=256,
            flags=SDR_IQ_FLAG_DISCONTINUITY | SDR_IQ_FLAG_CONFIG_CHANGED,
            decimation=250,
            payload_bytes=1024,
        )
        packed = header.pack()
        self.assertEqual(len(packed), IQ_HEADER_SIZE)
        unpacked = SdrIqHeader.unpack(packed)
        self.assertEqual(unpacked.stream_id, 1)
        self.assertEqual(unpacked.seq, 123)
        self.assertEqual(unpacked.payload_bytes, 1024)
        self.assertEqual(unpacked.next_timestamp_delta, 64_000)

    def test_iq_header_rejects_bad_payload_size(self) -> None:
        header = SdrIqHeader(sample_count=256, payload_bytes=512)
        with self.assertRaises(PacketError):
            header.pack()

    def test_psd_header_is_72_bytes_and_round_trips(self) -> None:
        header = SdrPsdHeader(
            frame_seq=7,
            adc_timestamp=100,
            start_frequency_hz=500_000,
            bin_spacing_millihz=15_259_000,
            fft_size=16384,
            total_bins=4096,
            segment_index=0,
            segment_count=8,
            bin_start=0,
            bin_count=512,
            payload_bytes=1024,
            stop_frequency_hz=108_000_000,
        )
        packed = header.pack()
        self.assertEqual(len(packed), PSD_HEADER_SIZE)
        unpacked = SdrPsdHeader.unpack(packed)
        self.assertEqual(unpacked.frame_seq, 7)
        self.assertEqual(unpacked.bin_count, 512)
        self.assertEqual(unpacked.payload_bytes, 1024)
        self.assertEqual(unpacked.stop_frequency_hz, 108_000_000)


if __name__ == "__main__":
    unittest.main()
