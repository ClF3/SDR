#!/usr/bin/env python3
"""Print AC920 control responses and UDP status while trying RX."""

from __future__ import annotations

import argparse
import json
import socket
import sys
import time
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from common.protocol import build_request, decode_json_line, encode_json_line  # noqa: E402


def request(tcp: socket.socket, reader: Any, request_id: int, cmd: str, **fields: Any) -> dict[str, Any]:
    tcp.sendall(encode_json_line(build_request(request_id, cmd, **fields)))
    line = reader.readline()
    if not line:
        raise RuntimeError(f"{cmd}: device closed TCP connection")
    response = decode_json_line(line)
    print(f"TCP {cmd}:")
    print(json.dumps(response, indent=2, sort_keys=True))
    return response


def recv_udp(sock: socket.socket, label: str, duration_s: float) -> None:
    deadline = time.monotonic() + duration_s
    sock.settimeout(0.5)
    count = 0
    while time.monotonic() < deadline:
        try:
            data, addr = sock.recvfrom(65535)
        except socket.timeout:
            continue
        count += 1
        text = data.decode("utf-8", errors="replace")
        print(f"UDP {label} #{count}: {len(data)} bytes from {addr[0]}:{addr[1]}")
        if text.startswith("{"):
            try:
                print(json.dumps(json.loads(text), indent=2, sort_keys=True))
            except json.JSONDecodeError:
                print(text)
        else:
            print(data[:96].hex())
    if count == 0:
        print(f"UDP {label}: no packets in {duration_s:.1f}s")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("host", default="192.168.10.2")
    parser.add_argument("--destination-ip", default="192.168.10.1")
    parser.add_argument("--timeout", type=float, default=5.0)
    args = parser.parse_args(argv)

    status_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    status_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    status_sock.bind(("0.0.0.0", 9003))

    iq_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    iq_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    iq_sock.bind(("0.0.0.0", 9001))

    with socket.create_connection((args.host, 9000), timeout=args.timeout) as tcp:
        with tcp.makefile("rb") as reader:
            request_id = 1
            request(
                tcp,
                reader,
                request_id,
                "hello",
                protocol_version=1,
                client_name="ac920-debug-probe",
                udp={
                    "destination_ip": args.destination_ip,
                    "iq_port": 9001,
                    "psd_port": 9002,
                    "status_port": 9003,
                },
            )
            request_id += 1
            recv_udp(status_sock, "status before rx", 1.0)

            request(tcp, reader, request_id, "get_status")
            request_id += 1

            request(
                tcp,
                reader,
                request_id,
                "set_rx",
                stream_id=0,
                adc_channel=0,
                frequency_hz=98_500_000,
                mode="WFM",
                iq_sample_rate_hz=1_000_000,
                bandwidth_hz=250_000,
                sample_format="SC16_LE",
                enable=True,
            )
            request_id += 1
            recv_udp(status_sock, "status after rx", 4.0)
            recv_udp(iq_sock, "iq", 4.0)

            request(tcp, reader, request_id, "get_status")
            request_id += 1
            request(tcp, reader, request_id, "stop_all")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
