from __future__ import annotations

import asyncio
import socket
import unittest

from common.protocol import IQ_HEADER_SIZE, PSD_HEADER_SIZE, SdrIqHeader, SdrPsdHeader
from rpi.backend.sdr_backend.config import DeviceConfig, UdpConfig
from rpi.backend.sdr_backend.device_client import DeviceClient
from simulator.fake_ac920 import FakeAc920Config, FakeAc920Server


def free_port() -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return int(port)


class FakeAc920IntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.control_port = free_port()
        self.iq_port = free_port()
        self.psd_port = free_port()
        self.status_port = free_port()
        self.server = FakeAc920Server(
            FakeAc920Config(
                bind_host="127.0.0.1",
                control_port=self.control_port,
                scenario="am_tone",
            )
        )
        await self.server.start()

    async def asyncTearDown(self) -> None:
        await self.server.stop()

    async def test_hello_set_rx_and_receive_iq(self) -> None:
        iq_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        iq_sock.bind(("127.0.0.1", self.iq_port))
        iq_sock.settimeout(2.0)
        self.addCleanup(iq_sock.close)

        client = DeviceClient(
            DeviceConfig(host="127.0.0.1", control_port=self.control_port),
            UdpConfig(
                bind_host="127.0.0.1",
                iq_port=self.iq_port,
                psd_port=self.psd_port,
                status_port=self.status_port,
            ),
        )
        hello = await client.connect()
        self.assertTrue(hello["ok"])
        response = await client.set_rx(
            stream_id=0,
            adc_channel=0,
            frequency_hz=1_000_000,
            mode="AM",
            iq_sample_rate_hz=250_000,
            bandwidth_hz=12_000,
            sample_format="SC16_LE",
            enable=True,
        )
        self.assertTrue(response["ok"])
        data = await asyncio.to_thread(iq_sock.recv, 2048)
        header = SdrIqHeader.unpack(data[:IQ_HEADER_SIZE])
        self.assertEqual(header.seq, 0)
        self.assertEqual(header.sample_count, 256)
        self.assertEqual(len(data) - IQ_HEADER_SIZE, header.payload_bytes)
        await client.close()

    async def test_set_psd_and_receive_wideband_segments(self) -> None:
        psd_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        psd_sock.bind(("127.0.0.1", self.psd_port))
        psd_sock.settimeout(2.0)
        self.addCleanup(psd_sock.close)

        client = DeviceClient(
            DeviceConfig(host="127.0.0.1", control_port=self.control_port),
            UdpConfig(
                bind_host="127.0.0.1",
                iq_port=self.iq_port,
                psd_port=self.psd_port,
                status_port=self.status_port,
            ),
        )
        hello = await client.connect()
        self.assertTrue(hello["ok"])
        response = await client.set_psd(
            psd_id=0,
            source="adc0",
            enable=True,
            start_frequency_hz=500_000,
            stop_frequency_hz=108_000_000,
            fft_size=16_384,
            output_bins=4096,
            fps=10,
            sample_format="I16_DBFS_Q8",
        )
        self.assertTrue(response["ok"])

        headers: list[SdrPsdHeader] = []
        frame_seq = None
        while len(headers) < 8:
            data = await asyncio.to_thread(psd_sock.recv, 2048)
            header = SdrPsdHeader.unpack(data[:PSD_HEADER_SIZE])
            if frame_seq is None:
                frame_seq = header.frame_seq
            if header.frame_seq == frame_seq:
                headers.append(header)
                self.assertEqual(len(data) - PSD_HEADER_SIZE, header.payload_bytes)

        self.assertEqual({header.segment_index for header in headers}, set(range(8)))
        self.assertEqual(headers[0].total_bins, 4096)
        self.assertEqual(headers[0].bin_count, 512)
        self.assertEqual(headers[0].stop_frequency_hz, 108_000_000)
        await client.close()

    async def test_set_psd_zoom_range_changes_bin_spacing(self) -> None:
        psd_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        psd_sock.bind(("127.0.0.1", self.psd_port))
        psd_sock.settimeout(2.0)
        self.addCleanup(psd_sock.close)

        client = DeviceClient(
            DeviceConfig(host="127.0.0.1", control_port=self.control_port),
            UdpConfig(
                bind_host="127.0.0.1",
                iq_port=self.iq_port,
                psd_port=self.psd_port,
                status_port=self.status_port,
            ),
        )
        await client.connect()
        response = await client.set_psd(
            psd_id=0,
            source="adc0",
            enable=True,
            start_frequency_hz=98_000_000,
            stop_frequency_hz=99_000_000,
            fft_size=16_384,
            output_bins=4096,
            fps=10,
            sample_format="I16_DBFS_Q8",
        )
        self.assertTrue(response["ok"])

        data = await asyncio.to_thread(psd_sock.recv, 2048)
        header = SdrPsdHeader.unpack(data[:PSD_HEADER_SIZE])
        self.assertEqual(header.start_frequency_hz, 98_000_000)
        self.assertEqual(header.stop_frequency_hz, 99_000_000)
        self.assertEqual(header.total_bins, 4096)
        self.assertLess(header.bin_spacing_millihz, 300_000)
        await client.close()


if __name__ == "__main__":
    unittest.main()
