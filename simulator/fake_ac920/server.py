"""Async fake AC920 device implementing the v1 network protocol."""

from __future__ import annotations

import argparse
import asyncio
from dataclasses import dataclass, field
import json
import socket
import time
from typing import Any

from common.protocol import (
    SDR_IQ_FLAG_ADC_OR,
    SDR_IQ_FLAG_CONFIG_CHANGED,
    SDR_IQ_FLAG_DISCONTINUITY,
    SDR_IQ_FLAG_FIFO_OVERFLOW,
    SdrIqHeader,
    build_error,
    build_response,
    decode_json_line,
    encode_json_line,
)

from .signal_gen import ComplexOscillator, complex_to_sc16


@dataclass(slots=True)
class FakeAc920Config:
    bind_host: str = "127.0.0.1"
    control_port: int = 9000
    scenario: str = "wfm_tone"
    sample_count: int = 256
    drop_every: int = 0
    inject_adc_or: bool = False
    inject_fifo_overflow: bool = False
    status_interval_active_s: float = 0.2
    status_interval_idle_s: float = 1.0


@dataclass(slots=True)
class StreamState:
    stream_id: int
    adc_channel: int = 0
    frequency_hz: int = 98_500_000
    mode: str = "WFM"
    iq_sample_rate_hz: int = 1_000_000
    bandwidth_hz: int = 250_000
    enabled: bool = False
    seq: int = 0
    adc_timestamp: int = 0
    first_packet: bool = True
    fifo_overflow_count: int = 0
    oscillator: ComplexOscillator = field(default_factory=lambda: ComplexOscillator(1_000_000))

    @property
    def decimation(self) -> int:
        return int(250_000_000 // self.iq_sample_rate_hz)

    def reset_for_enable(self) -> None:
        self.seq = 0
        self.adc_timestamp = 0
        self.first_packet = True
        self.oscillator = ComplexOscillator(self.iq_sample_rate_hz)


class FakeAc920Server:
    def __init__(self, config: FakeAc920Config) -> None:
        self.config = config
        self._server: asyncio.AbstractServer | None = None
        self._owner: asyncio.StreamWriter | None = None
        self._udp_dest: tuple[str, int] | None = None
        self._udp_status_dest: tuple[str, int] | None = None
        self._udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._tx_task: asyncio.Task[None] | None = None
        self._status_task: asyncio.Task[None] | None = None
        self._status_seq = 0
        self._frontend = {"attenuator_db": 10, "lna": "bypass", "filter": "LPF_108M"}
        self._streams: dict[int, StreamState] = {0: StreamState(0), 1: StreamState(1)}
        self._iq_packets_sent = 0
        self._psd_packets_sent = 0
        self._boot_time = time.monotonic()

    async def start(self) -> None:
        self._server = await asyncio.start_server(
            self._handle_client,
            host=self.config.bind_host,
            port=self.config.control_port,
        )
        self._status_task = asyncio.create_task(self._status_loop())

    async def serve_forever(self) -> None:
        await self.start()
        assert self._server is not None
        async with self._server:
            await self._server.serve_forever()

    async def stop(self) -> None:
        if self._server:
            self._server.close()
            await self._server.wait_closed()
        if self._tx_task:
            self._tx_task.cancel()
        if self._status_task:
            self._status_task.cancel()
        self._udp_sock.close()

    async def _handle_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        if self._owner is not None and not self._owner.is_closing():
            writer.write(
                encode_json_line(
                    build_error(None, "busy", "device already has an owner")
                )
            )
            await writer.drain()
            writer.close()
            await writer.wait_closed()
            return

        peer = writer.get_extra_info("peername")
        peer_ip = peer[0] if peer else "127.0.0.1"
        self._owner = writer
        try:
            while not reader.at_eof():
                line = await reader.readline()
                if not line:
                    break
                response = await self._dispatch(line, peer_ip)
                writer.write(encode_json_line(response))
                await writer.drain()
        finally:
            if self._owner is writer:
                await self._stop_all()
                self._owner = None
                self._udp_dest = None
                self._udp_status_dest = None
            writer.close()
            await writer.wait_closed()

    async def _dispatch(self, line: bytes, peer_ip: str) -> dict[str, Any]:
        try:
            request = decode_json_line(line)
        except Exception:
            return build_error(None, "invalid_json", "request is not valid JSON")

        request_id = request.get("request_id")
        cmd = request.get("cmd")
        if not isinstance(request_id, int):
            return build_error(None, "invalid_field", "request_id is required")
        if not isinstance(cmd, str):
            return build_error(request_id, "invalid_field", "cmd is required")

        try:
            if cmd == "hello":
                return self._cmd_hello(request_id, request, peer_ip)
            if cmd == "ping":
                return build_response(
                    request_id,
                    client_time_ms=request.get("client_time_ms"),
                    device_time_ms=self._device_time_ms(),
                )
            if cmd == "get_status":
                return build_response(request_id, status=self._status_object())
            if cmd == "set_frontend":
                return self._cmd_set_frontend(request_id, request)
            if cmd == "set_rx":
                return await self._cmd_set_rx(request_id, request)
            if cmd == "stop_all":
                await self._stop_all()
                return build_response(request_id)
            if cmd == "set_psd":
                return build_response(
                    request_id,
                    applied={
                        "psd_id": int(request.get("psd_id", 0)),
                        "enabled": bool(request.get("enable", False)),
                    },
                )
            return build_error(request_id, "invalid_command", f"unknown command {cmd}")
        except (TypeError, ValueError) as exc:
            return build_error(request_id, "invalid_field", str(exc))

    def _cmd_hello(self, request_id: int, request: dict[str, Any], peer_ip: str) -> dict[str, Any]:
        if request.get("protocol_version") != 1:
            return build_error(request_id, "unsupported_version", "protocol_version must be 1")
        udp = request.get("udp")
        if not isinstance(udp, dict):
            return build_error(request_id, "invalid_field", "udp is required")
        dest_ip = str(udp.get("destination_ip") or peer_ip)
        self._udp_dest = (dest_ip, int(udp["iq_port"]))
        self._udp_status_dest = (dest_ip, int(udp["status_port"]))
        return build_response(
            request_id,
            protocol_version=1,
            device={
                "name": "fake-AC920-ACFL3432",
                "serial": "fake",
                "firmware_version": "0.1.0",
                "fpga_build_id": "fake",
            },
            limits={
                "adc_sample_rate_hz": 250_000_000,
                "min_frequency_hz": 500_000,
                "max_frequency_hz": 108_000_000,
                "max_iq_streams": 2,
                "supported_iq_sample_rates_hz": [125_000, 250_000, 500_000, 1_000_000],
                "supported_sample_formats": ["SC16_LE"],
                "max_udp_payload_bytes": 1200,
            },
        )

    def _cmd_set_frontend(self, request_id: int, request: dict[str, Any]) -> dict[str, Any]:
        if "attenuator_db" in request:
            attenuator_db = int(request["attenuator_db"])
            if attenuator_db not in (0, 10, 20, 30):
                return build_error(request_id, "out_of_range", "attenuator_db must be 0/10/20/30")
            self._frontend["attenuator_db"] = attenuator_db
        if "lna" in request:
            lna = str(request["lna"])
            if lna not in ("on", "bypass"):
                return build_error(request_id, "invalid_field", "lna must be on or bypass")
            self._frontend["lna"] = lna
        if "filter" in request:
            self._frontend["filter"] = str(request["filter"])
        return build_response(request_id, applied=dict(self._frontend))

    async def _cmd_set_rx(self, request_id: int, request: dict[str, Any]) -> dict[str, Any]:
        stream_id = int(request.get("stream_id", 0))
        if stream_id not in self._streams:
            return build_error(request_id, "out_of_range", "unsupported stream_id")
        stream = self._streams[stream_id]
        enable = bool(request.get("enable", stream.enabled))
        if not enable:
            stream.enabled = False
            return build_response(request_id, applied={"stream_id": stream_id, "enable": False})

        stream.adc_channel = int(request.get("adc_channel", stream.adc_channel))
        stream.frequency_hz = int(request.get("frequency_hz", stream.frequency_hz))
        stream.mode = str(request.get("mode", stream.mode))
        stream.iq_sample_rate_hz = int(request.get("iq_sample_rate_hz", stream.iq_sample_rate_hz))
        stream.bandwidth_hz = int(request.get("bandwidth_hz", stream.bandwidth_hz))
        if stream.iq_sample_rate_hz not in (125_000, 250_000, 500_000, 1_000_000):
            return build_error(request_id, "out_of_range", "unsupported iq_sample_rate_hz")
        stream.enabled = True
        stream.reset_for_enable()
        if self._tx_task is None or self._tx_task.done():
            self._tx_task = asyncio.create_task(self._iq_loop())
        return build_response(
            request_id,
            applied={
                "stream_id": stream.stream_id,
                "adc_channel": stream.adc_channel,
                "frequency_hz": stream.frequency_hz,
                "mode": stream.mode,
                "iq_sample_rate_hz": stream.iq_sample_rate_hz,
                "bandwidth_hz": stream.bandwidth_hz,
                "sample_format": "SC16_LE",
                "decimation": stream.decimation,
                "enable": True,
            },
        )

    async def _stop_all(self) -> None:
        for stream in self._streams.values():
            stream.enabled = False

    async def _iq_loop(self) -> None:
        while True:
            active = [stream for stream in self._streams.values() if stream.enabled]
            if not active:
                await asyncio.sleep(0.05)
                continue
            if self._udp_dest is None:
                await asyncio.sleep(0.05)
                continue
            for stream in active:
                self._send_iq_packet(stream)
            min_rate = max(stream.iq_sample_rate_hz for stream in active)
            await asyncio.sleep(self.config.sample_count / min_rate)

    def _send_iq_packet(self, stream: StreamState) -> None:
        iq = stream.oscillator.make_iq(self.config.scenario, self.config.sample_count)
        payload = complex_to_sc16(iq)
        flags = 0
        if stream.first_packet:
            flags |= SDR_IQ_FLAG_DISCONTINUITY | SDR_IQ_FLAG_CONFIG_CHANGED
            stream.first_packet = False
        if self.config.inject_adc_or:
            flags |= SDR_IQ_FLAG_ADC_OR
        if self.config.inject_fifo_overflow:
            flags |= SDR_IQ_FLAG_FIFO_OVERFLOW
            stream.fifo_overflow_count += 1
        header = SdrIqHeader(
            stream_id=stream.stream_id,
            seq=stream.seq,
            adc_timestamp=stream.adc_timestamp,
            frequency_hz=stream.frequency_hz,
            iq_sample_rate_hz=stream.iq_sample_rate_hz,
            bandwidth_hz=stream.bandwidth_hz,
            sample_count=self.config.sample_count,
            flags=flags,
            decimation=stream.decimation,
            payload_bytes=len(payload),
        )
        self._iq_packets_sent += 1
        should_drop = self.config.drop_every > 0 and self._iq_packets_sent % self.config.drop_every == 0
        if not should_drop and self._udp_dest is not None:
            self._udp_sock.sendto(header.pack() + payload, self._udp_dest)
        stream.seq = (stream.seq + 1) & 0xFFFFFFFF
        stream.adc_timestamp = (stream.adc_timestamp + header.next_timestamp_delta) & 0xFFFFFFFFFFFFFFFF

    async def _status_loop(self) -> None:
        while True:
            active = any(stream.enabled for stream in self._streams.values())
            if self._udp_status_dest is not None:
                payload = json.dumps(self._status_object(), separators=(",", ":")).encode("utf-8")
                self._udp_sock.sendto(payload, self._udp_status_dest)
            await asyncio.sleep(
                self.config.status_interval_active_s if active else self.config.status_interval_idle_s
            )

    def _status_object(self) -> dict[str, Any]:
        self._status_seq += 1
        streams = [
            {
                "stream_id": stream.stream_id,
                "adc_channel": stream.adc_channel,
                "enabled": stream.enabled,
                "frequency_hz": stream.frequency_hz,
                "mode": stream.mode,
                "iq_sample_rate_hz": stream.iq_sample_rate_hz,
                "bandwidth_hz": stream.bandwidth_hz,
                "sample_format": "SC16_LE",
                "seq": stream.seq,
                "fifo_overflow_count": stream.fifo_overflow_count,
            }
            for stream in self._streams.values()
            if stream.enabled
        ]
        return {
            "type": "status",
            "protocol_version": 1,
            "seq": self._status_seq,
            "device_time_ms": self._device_time_ms(),
            "adc_sample_rate_hz": 250_000_000,
            "adc": {
                "channel": 0,
                "peak_dbfs": -14.5,
                "rms_dbfs": -31.2,
                "or_count": self._iq_packets_sent if self.config.inject_adc_or else 0,
                "clip_count": 0,
            },
            "frontend": dict(self._frontend),
            "streams": streams,
            "psd": [{"psd_id": 0, "enabled": False}],
            "network": {
                "iq_packets_sent": self._iq_packets_sent,
                "psd_packets_sent": self._psd_packets_sent,
                "status_packets_sent": self._status_seq,
                "iq_fifo_overflow_count": sum(s.fifo_overflow_count for s in self._streams.values()),
                "psd_fifo_overflow_count": 0,
            },
        }

    def _device_time_ms(self) -> int:
        return int((time.monotonic() - self._boot_time) * 1000)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fake AC920 SDR network endpoint")
    parser.add_argument("--bind", default="127.0.0.1", help="control server bind address")
    parser.add_argument("--port", type=int, default=9000, help="TCP control port")
    parser.add_argument(
        "--scenario",
        default="wfm_tone",
        choices=["tone", "am_tone", "ssb_tone", "nfm_tone", "wfm_tone", "noise"],
    )
    parser.add_argument("--drop-every", type=int, default=0, help="drop every Nth IQ packet")
    parser.add_argument("--adc-or", action="store_true", help="set ADC OR flag in IQ/status")
    parser.add_argument("--fifo-overflow", action="store_true", help="set FIFO overflow flag")
    return parser.parse_args()


async def async_main() -> None:
    args = parse_args()
    server = FakeAc920Server(
        FakeAc920Config(
            bind_host=args.bind,
            control_port=args.port,
            scenario=args.scenario,
            drop_every=args.drop_every,
            inject_adc_or=args.adc_or,
            inject_fifo_overflow=args.fifo_overflow,
        )
    )
    print(f"fake AC920 listening on {args.bind}:{args.port} scenario={args.scenario}", flush=True)
    await server.serve_forever()


def main() -> None:
    try:
        asyncio.run(async_main())
    except KeyboardInterrupt:
        pass

