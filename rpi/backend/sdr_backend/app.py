"""ASGI app factory for the Raspberry Pi backend.

The first backend revision used FastAPI route decorators. On the Raspberry Pi
test image, the very new FastAPI/Starlette combination rejected valid frontend
requests with 422/403 before our handlers ran. This module keeps the same
public HTTP/WebSocket interface, but handles those routes directly as ASGI so
bring-up behavior is deterministic and easy to debug.
"""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
import json
from typing import Any
from urllib.parse import parse_qs

from .config import AppConfig
from .runtime import BackendRuntime

Scope = dict[str, Any]
Message = dict[str, Any]
Receive = Callable[[], Awaitable[Message]]
Send = Callable[[Message], Awaitable[None]]


class SdrAsgiApp:
    def __init__(self, config: AppConfig) -> None:
        self.runtime = BackendRuntime(config)
        self.routes = [
            "/api/status",
            "/api/device/connect",
            "/api/frontend",
            "/api/rx",
            "/api/psd",
            "/api/stop",
            "/api/raw-capture",
            "/api/debug/routes",
            "/ws/status",
            "/ws/spectrum",
            "/ws/audio",
        ]

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        scope_type = scope["type"]
        if scope_type == "lifespan":
            await self._lifespan(receive, send)
        elif scope_type == "http":
            await self._http(scope, receive, send)
        elif scope_type == "websocket":
            await self._websocket(scope, receive, send)
        else:
            raise RuntimeError(f"unsupported ASGI scope type {scope_type}")

    async def _lifespan(self, receive: Receive, send: Send) -> None:
        while True:
            message = await receive()
            if message["type"] == "lifespan.startup":
                try:
                    await self.runtime.start()
                except Exception as exc:
                    await send({"type": "lifespan.startup.failed", "message": str(exc)})
                else:
                    await send({"type": "lifespan.startup.complete"})
            elif message["type"] == "lifespan.shutdown":
                try:
                    await self.runtime.stop()
                finally:
                    await send({"type": "lifespan.shutdown.complete"})
                return

    async def _http(self, scope: Scope, receive: Receive, send: Send) -> None:
        method = scope["method"].upper()
        path = scope["path"]

        if method == "OPTIONS":
            await self._json_response(send, {"ok": True})
            return

        try:
            if method == "GET" and path == "/api/status":
                await self._json_response(send, self.runtime.snapshot())
                return

            if method == "GET" and path == "/api/debug/routes":
                await self._json_response(send, {"routes": self.routes})
                return

            if method == "POST" and path == "/api/device/connect":
                body = await self._read_json_body(receive)
                query = self._query(scope)
                host = body.get("host") or query.get("host", [None])[0]
                response = await self.runtime.connect_device(str(host) if host else None)
                await self._json_response(send, response)
                return

            if method == "POST" and path == "/api/frontend":
                body = await self._read_json_body(receive)
                fields = {
                    key: body[key]
                    for key in ("attenuator_db", "lna", "filter")
                    if key in body and body[key] is not None
                }
                await self._json_response(send, await self.runtime.set_frontend(fields))
                return

            if method == "POST" and path == "/api/rx":
                body = await self._read_json_body(receive)
                fields = {
                    "stream_id": 0,
                    "adc_channel": 0,
                    "frequency_hz": 98_500_000,
                    "mode": "WFM",
                    "iq_sample_rate_hz": 1_000_000,
                    "bandwidth_hz": 250_000,
                    "sample_format": "SC16_LE",
                    "enable": True,
                }
                fields.update({key: value for key, value in body.items() if value is not None})
                await self._json_response(send, await self.runtime.set_rx(fields))
                return

            if method == "POST" and path == "/api/psd":
                body = await self._read_json_body(receive)
                await self._json_response(send, await self.runtime.set_psd(body))
                return

            if method == "POST" and path == "/api/stop":
                await self._read_body(receive)
                await self._json_response(send, await self.runtime.stop_all())
                return

            if method == "POST" and path == "/api/raw-capture":
                body = await self._read_json_body(receive)
                response = await self.runtime.raw_capture(
                    int(body.get("adc_channel", 0)),
                    int(body.get("sample_count", 65_536)),
                )
                await self._json_response(send, response)
                return

            await self._json_response(send, {"ok": False, "error": "not found"}, status=404)
        except Exception as exc:
            await self._json_response(
                send,
                {"ok": False, "error": {"code": "internal_error", "message": str(exc)}},
                status=500,
            )

    async def _websocket(self, scope: Scope, receive: Receive, send: Send) -> None:
        path = scope["path"]
        if path not in ("/ws/status", "/ws/spectrum", "/ws/audio"):
            await send({"type": "websocket.close", "code": 1008})
            return

        message = await receive()
        if message["type"] != "websocket.connect":
            await send({"type": "websocket.close", "code": 1002})
            return

        await send({"type": "websocket.accept"})
        try:
            if path == "/ws/status":
                await self._send_ws_json(send, self.runtime.snapshot())
                async with self.runtime.status.subscribe() as queue:
                    await self._ws_queue_loop(queue, receive, send, json_messages=True)
            elif path == "/ws/spectrum":
                async with self.runtime.spectrum.subscribe() as queue:
                    await self._ws_queue_loop(queue, receive, send, json_messages=True)
            elif path == "/ws/audio":
                async with self.runtime.audio.subscribe() as queue:
                    await self._ws_queue_loop(queue, receive, send, json_messages=False)
        except (asyncio.CancelledError, RuntimeError):
            return

    async def _ws_queue_loop(
        self,
        queue: asyncio.Queue[Any],
        receive: Receive,
        send: Send,
        *,
        json_messages: bool,
    ) -> None:
        while True:
            queue_task = asyncio.create_task(queue.get())
            receive_task = asyncio.create_task(receive())
            done, pending = await asyncio.wait(
                {queue_task, receive_task},
                return_when=asyncio.FIRST_COMPLETED,
            )
            for task in pending:
                task.cancel()

            if receive_task in done:
                message = receive_task.result()
                if message["type"] == "websocket.disconnect":
                    return
                continue

            item = queue_task.result()
            if json_messages:
                await self._send_ws_json(send, item)
            else:
                await send({"type": "websocket.send", "bytes": item})

    async def _read_body(self, receive: Receive) -> bytes:
        chunks = []
        while True:
            message = await receive()
            if message["type"] != "http.request":
                break
            chunks.append(message.get("body", b""))
            if not message.get("more_body", False):
                break
        return b"".join(chunks)

    async def _read_json_body(self, receive: Receive) -> dict[str, Any]:
        body = await self._read_body(receive)
        if not body:
            return {}
        try:
            value = json.loads(body.decode("utf-8"))
        except Exception:
            return {}
        return value if isinstance(value, dict) else {}

    def _query(self, scope: Scope) -> dict[str, list[str]]:
        raw = scope.get("query_string", b"")
        return parse_qs(raw.decode("utf-8")) if raw else {}

    async def _json_response(
        self,
        send: Send,
        payload: dict[str, Any],
        *,
        status: int = 200,
    ) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        await send(
            {
                "type": "http.response.start",
                "status": status,
                "headers": [
                    (b"content-type", b"application/json; charset=utf-8"),
                    (b"content-length", str(len(body)).encode("ascii")),
                    (b"access-control-allow-origin", b"*"),
                    (b"access-control-allow-methods", b"GET,POST,OPTIONS"),
                    (b"access-control-allow-headers", b"*"),
                ],
            }
        )
        await send({"type": "http.response.body", "body": body})

    async def _send_ws_json(self, send: Send, payload: dict[str, Any]) -> None:
        await send(
            {
                "type": "websocket.send",
                "text": json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            }
        )


def create_app(config: AppConfig) -> SdrAsgiApp:
    return SdrAsgiApp(config)
