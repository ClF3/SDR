from __future__ import annotations

import asyncio
import socket
import unittest

from rpi.backend.sdr_backend.config import AppConfig, DeviceConfig, UdpConfig
from rpi.backend.sdr_backend.runtime import BackendRuntime
from simulator.fake_ac920 import FakeAc920Config, FakeAc920Server


def free_port() -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return int(port)


class BackendPsdPipelineTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.control_port = free_port()
        self.iq_port = free_port()
        self.psd_port = free_port()
        self.status_port = free_port()
        self.server = FakeAc920Server(
            FakeAc920Config(bind_host="127.0.0.1", control_port=self.control_port)
        )
        await self.server.start()
        self.runtime = BackendRuntime(
            AppConfig(
                device=DeviceConfig(host="127.0.0.1", control_port=self.control_port),
                udp=UdpConfig(
                    bind_host="127.0.0.1",
                    iq_port=self.iq_port,
                    psd_port=self.psd_port,
                    status_port=self.status_port,
                ),
            )
        )
        await self.runtime.start()

    async def asyncTearDown(self) -> None:
        await self.runtime.stop()
        await self.server.stop()

    async def test_fake_psd_reaches_backend_spectrum_broadcaster(self) -> None:
        async with self.runtime.spectrum.subscribe() as queue:
            hello = await self.runtime.connect_device()
            self.assertTrue(hello["ok"])
            frame = await asyncio.wait_for(queue.get(), timeout=2.0)

        self.assertEqual(frame["type"], "wideband_psd")
        self.assertEqual(frame["start_frequency_hz"], 500_000)
        self.assertEqual(frame["stop_frequency_hz"], 108_000_000)
        self.assertEqual(len(frame["bins_dbfs"]), 4096)
        self.assertEqual(self.runtime.snapshot()["psd"]["frame_seq"], frame["frame_seq"])


if __name__ == "__main__":
    unittest.main()
