"""Application runtime wiring device IO, DSP, state, and broadcasters."""

from __future__ import annotations

import asyncio
from dataclasses import asdict
from pathlib import Path
from typing import Any

from common.protocol import SdrIqHeader, SdrPsdHeader

from .broadcast import Broadcaster
from .config import AppConfig
from .device_client import DeviceClient
from .dsp import Demodulator
from .raw_capture import capture_raw
from .state import AppState
from .udp_receiver import UdpReceivers
from .waterfall import WaterfallEngine


class BackendRuntime:
    def __init__(self, config: AppConfig) -> None:
        self.config = config
        self.state = AppState(frontend=asdict(config.frontend), rx=asdict(config.rx))
        self.device = DeviceClient(config.device, config.udp)
        self.audio = Broadcaster[bytes](max_queue=128)
        self.status = Broadcaster[dict[str, Any]](max_queue=32)
        self.spectrum = Broadcaster[dict[str, Any]](max_queue=16)
        self.demod = Demodulator(
            audio_sample_rate_hz=config.dsp.audio_sample_rate_hz,
            audio_frame_ms=config.dsp.audio_frame_ms,
            wfm_deemphasis_us=config.dsp.wfm_deemphasis_us,
        )
        self.waterfall = WaterfallEngine(config.dsp.fft_size)
        self._loop: asyncio.AbstractEventLoop | None = None
        self._udp: UdpReceivers | None = None

    async def start(self) -> None:
        self._loop = asyncio.get_running_loop()
        self._udp = UdpReceivers(
            self.config.udp.bind_host,
            self.config.udp.iq_port,
            self.config.udp.psd_port,
            self.config.udp.status_port,
            self._thread_iq,
            self._thread_psd,
            self._thread_status,
            self._thread_error,
        )
        self._udp.start()

    async def stop(self) -> None:
        await self.device.close()
        if self._udp:
            self._udp.stop()

    async def connect_device(self, host: str | None = None) -> dict[str, Any]:
        response = await self.device.connect(host)
        self.state.connected = True
        self.state.device_host = self.config.device.host
        self.state.hello = response
        self.status.publish(self.state.snapshot())
        return response

    async def set_frontend(self, fields: dict[str, Any]) -> dict[str, Any]:
        response = await self.device.set_frontend(**fields)
        self.state.frontend = response.get("applied", fields)
        self.status.publish(self.state.snapshot())
        return response

    async def set_rx(self, fields: dict[str, Any]) -> dict[str, Any]:
        response = await self.device.set_rx(**fields)
        applied = response.get("applied", fields)
        self.state.rx = applied
        mode = str(applied.get("mode", fields.get("mode", "WFM")))
        rate = int(applied.get("iq_sample_rate_hz", fields.get("iq_sample_rate_hz", 1_000_000)))
        self.demod.configure(mode, rate)
        self.status.publish(self.state.snapshot())
        return response

    async def stop_all(self) -> dict[str, Any]:
        response = await self.device.stop_all()
        self.state.rx = {**self.state.rx, "enable": False}
        self.status.publish(self.state.snapshot())
        return response

    async def raw_capture(self, adc_channel: int, sample_count: int) -> dict[str, Any]:
        path = Path("/tmp") / f"sdr_raw_ch{adc_channel}_{sample_count}.s16"
        return await capture_raw(
            self.config.device.host,
            self.config.device.raw_capture_port,
            adc_channel,
            sample_count,
            path,
        )

    def snapshot(self) -> dict[str, Any]:
        return self.state.snapshot()

    def _thread_iq(self, header: SdrIqHeader, payload: bytes) -> None:
        if self._loop:
            self._loop.call_soon_threadsafe(self._handle_iq, header, payload)

    def _thread_psd(self, header: SdrPsdHeader, payload: bytes) -> None:
        if self._loop:
            self._loop.call_soon_threadsafe(
                self.spectrum.publish,
                {
                    "type": "psd",
                    "psd_id": header.psd_id,
                    "frame_seq": header.frame_seq,
                    "bin_count": header.bin_count,
                    "payload_bytes": len(payload),
                },
            )

    def _thread_status(self, status: dict[str, Any]) -> None:
        if self._loop:
            self._loop.call_soon_threadsafe(self._handle_status, status)

    def _thread_error(self, exc: Exception) -> None:
        if self._loop:
            self._loop.call_soon_threadsafe(self._handle_error, exc)

    def _handle_iq(self, header: SdrIqHeader, payload: bytes) -> None:
        self.state.ingest_iq_header(header)
        self.demod.configure(str(self.state.rx.get("mode", "WFM")), header.iq_sample_rate_hz)
        for frame in self.demod.process_sc16(payload):
            self.audio.publish(frame)
        spectrum = self.waterfall.compute(payload, header.frequency_hz, header.iq_sample_rate_hz)
        if spectrum:
            spectrum["flags"] = header.flags
            self.spectrum.publish(spectrum)

    def _handle_status(self, status: dict[str, Any]) -> None:
        self.state.device_status = status
        self.status.publish(self.state.snapshot())

    def _handle_error(self, exc: Exception) -> None:
        self.state.last_error = str(exc)
        self.status.publish(self.state.snapshot())
