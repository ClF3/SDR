"""Blocking UDP receiver threads using recvfrom_into."""

from __future__ import annotations

from collections.abc import Callable
import json
import socket
import threading

from common.protocol import IQ_HEADER_SIZE, PSD_HEADER_SIZE, SdrIqHeader, SdrPsdHeader


IqCallback = Callable[[SdrIqHeader, bytes], None]
PsdCallback = Callable[[SdrPsdHeader, bytes], None]
StatusCallback = Callable[[dict], None]
ErrorCallback = Callable[[Exception], None]


class UdpReceivers:
    def __init__(
        self,
        bind_host: str,
        iq_port: int,
        psd_port: int,
        status_port: int,
        on_iq: IqCallback,
        on_psd: PsdCallback,
        on_status: StatusCallback,
        on_error: ErrorCallback,
    ) -> None:
        self.bind_host = bind_host
        self.iq_port = iq_port
        self.psd_port = psd_port
        self.status_port = status_port
        self.on_iq = on_iq
        self.on_psd = on_psd
        self.on_status = on_status
        self.on_error = on_error
        self._stop = threading.Event()
        self._threads: list[threading.Thread] = []
        self._sockets: list[socket.socket] = []

    def start(self) -> None:
        if self._threads:
            return
        self._start_socket("iq", self.iq_port, self._handle_iq)
        self._start_socket("psd", self.psd_port, self._handle_psd)
        self._start_socket("status", self.status_port, self._handle_status)

    def stop(self) -> None:
        self._stop.set()
        for sock in self._sockets:
            sock.close()
        for thread in self._threads:
            thread.join(timeout=1.0)
        self._threads.clear()
        self._sockets.clear()

    def _start_socket(self, name: str, port: int, handler: Callable[[memoryview, int], None]) -> None:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((self.bind_host, port))
        self._sockets.append(sock)
        thread = threading.Thread(
            target=self._loop,
            name=f"udp-{name}-{port}",
            args=(sock, handler),
            daemon=True,
        )
        thread.start()
        self._threads.append(thread)

    def _loop(self, sock: socket.socket, handler: Callable[[memoryview, int], None]) -> None:
        buffer = bytearray(65535)
        view = memoryview(buffer)
        while not self._stop.is_set():
            try:
                size, _addr = sock.recvfrom_into(buffer)
                handler(view[:size], size)
            except OSError:
                break
            except Exception as exc:
                self.on_error(exc)

    def _handle_iq(self, data: memoryview, size: int) -> None:
        if size < IQ_HEADER_SIZE:
            return
        header = SdrIqHeader.unpack(data[:IQ_HEADER_SIZE])
        payload = bytes(data[IQ_HEADER_SIZE : IQ_HEADER_SIZE + header.payload_bytes])
        self.on_iq(header, payload)

    def _handle_psd(self, data: memoryview, size: int) -> None:
        if size < PSD_HEADER_SIZE:
            return
        header = SdrPsdHeader.unpack(data[:PSD_HEADER_SIZE])
        payload = bytes(data[PSD_HEADER_SIZE : PSD_HEADER_SIZE + header.payload_bytes])
        self.on_psd(header, payload)

    def _handle_status(self, data: memoryview, size: int) -> None:
        self.on_status(json.loads(bytes(data[:size]).decode("utf-8")))

