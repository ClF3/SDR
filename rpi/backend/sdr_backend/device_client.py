"""TCP JSON Lines client for AC920 control plane."""

from __future__ import annotations

import asyncio
from contextlib import suppress
from typing import Any

from common.protocol import build_request, decode_json_line, encode_json_line

from .config import DeviceConfig, UdpConfig


class DeviceClientError(RuntimeError):
    pass


class DeviceClient:
    def __init__(self, device: DeviceConfig, udp: UdpConfig) -> None:
        self.device = device
        self.udp = udp
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._lock = asyncio.Lock()
        self._request_id = 0
        self._heartbeat_task: asyncio.Task[None] | None = None

    @property
    def connected(self) -> bool:
        return self._writer is not None and not self._writer.is_closing()

    async def connect(self, host: str | None = None) -> dict[str, Any]:
        if host:
            self.device.host = host
        await self.close()
        try:
            self._reader, self._writer = await asyncio.wait_for(
                asyncio.open_connection(self.device.host, self.device.control_port),
                timeout=5.0,
            )
            hello = await self.request(
                "hello",
                protocol_version=1,
                client_name=self.device.client_name,
                udp={
                    "iq_port": self.udp.iq_port,
                    "psd_port": self.udp.psd_port,
                    "status_port": self.udp.status_port,
                },
            )
        except (OSError, asyncio.TimeoutError) as exc:
            await self.close()
            raise DeviceClientError(
                f"could not connect to {self.device.host}:{self.device.control_port}: {exc}"
            ) from exc
        except Exception:
            await self.close()
            raise
        self._heartbeat_task = asyncio.create_task(self._heartbeat_loop())
        return hello

    async def close(self) -> None:
        if self._heartbeat_task:
            task = self._heartbeat_task
            self._heartbeat_task = None
            if task is not asyncio.current_task():
                task.cancel()
                with suppress(asyncio.CancelledError):
                    await task
        if self._writer:
            self._writer.close()
            try:
                await self._writer.wait_closed()
            except Exception:
                pass
        self._reader = None
        self._writer = None

    async def request(self, cmd: str, **fields: Any) -> dict[str, Any]:
        if self._reader is None or self._writer is None:
            raise DeviceClientError("device is not connected")
        async with self._lock:
            self._request_id += 1
            request_id = self._request_id
            self._writer.write(encode_json_line(build_request(request_id, cmd, **fields)))
            await self._writer.drain()
            line = await asyncio.wait_for(self._reader.readline(), timeout=5.0)
            if not line:
                raise DeviceClientError("device closed control connection")
            response = decode_json_line(line)
            if response.get("request_id") != request_id:
                raise DeviceClientError("response request_id mismatch")
            if not response.get("ok", False):
                error = response.get("error") or {}
                raise DeviceClientError(f"{error.get('code', 'error')}: {error.get('message', '')}")
            return response

    async def set_frontend(self, **fields: Any) -> dict[str, Any]:
        return await self.request("set_frontend", **fields)

    async def set_rx(self, **fields: Any) -> dict[str, Any]:
        return await self.request("set_rx", **fields)

    async def set_psd(self, **fields: Any) -> dict[str, Any]:
        return await self.request("set_psd", **fields)

    async def stop_all(self) -> dict[str, Any]:
        return await self.request("stop_all")

    async def get_status(self) -> dict[str, Any]:
        return await self.request("get_status")

    async def _heartbeat_loop(self) -> None:
        try:
            while True:
                await asyncio.sleep(2.0)
                if self.connected:
                    await self.request("ping", client_time_ms=0)
        except asyncio.CancelledError:
            raise
        except Exception:
            await self.close()
