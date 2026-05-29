#!/usr/bin/env python3
"""Probe the AC920 v1 control and UDP data paths.

This is intentionally a plain socket tool so it can run on the Raspberry Pi
without starting the Web backend. It separates the most common bring-up failures:

* no TCP listener on port 9000
* hello/control protocol mismatch
* TCP works, but UDP IQ/PSD/status packets do not return to the Pi
"""

from __future__ import annotations

import argparse
from pathlib import Path
import socket
import sys
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from common.protocol import (  # noqa: E402
    IQ_HEADER_SIZE,
    PSD_HEADER_SIZE,
    SdrIqHeader,
    SdrPsdHeader,
    build_request,
    decode_json_line,
    encode_json_line,
)


class ProbeError(RuntimeError):
    pass


def _udp_socket(bind_host: str, port: int) -> socket.socket:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((bind_host, port))
    return sock


def _request(
    tcp: socket.socket,
    reader: Any,
    request_id: int,
    cmd: str,
    **fields: Any,
) -> dict[str, Any]:
    tcp.sendall(encode_json_line(build_request(request_id, cmd, **fields)))
    line = reader.readline()
    if not line:
        raise ProbeError(f"{cmd}: device closed TCP control connection")
    response = decode_json_line(line)
    if response.get("request_id") != request_id:
        raise ProbeError(
            f"{cmd}: response request_id {response.get('request_id')} != {request_id}"
        )
    if not response.get("ok", False):
        error = response.get("error") or {}
        raise ProbeError(f"{cmd}: {error.get('code', 'error')}: {error.get('message', '')}")
    return response


def _recv(sock: socket.socket, label: str, timeout_s: float) -> tuple[bytes, tuple[str, int]]:
    sock.settimeout(timeout_s)
    try:
        data, addr = sock.recvfrom(65535)
    except socket.timeout as exc:
        raise ProbeError(f"{label}: timed out waiting for UDP packet") from exc
    return data, (str(addr[0]), int(addr[1]))


def _print_json_summary(prefix: str, response: dict[str, Any]) -> None:
    keys = ", ".join(sorted(key for key in response if key not in {"ok", "request_id"}))
    print(f"OK {prefix}: request_id={response.get('request_id')} fields=[{keys}]")


def run_probe(args: argparse.Namespace) -> int:
    iq_sock = _udp_socket(args.bind_host, args.iq_port)
    psd_sock = _udp_socket(args.bind_host, args.psd_port)
    status_sock = _udp_socket(args.bind_host, args.status_port)

    try:
        print(f"TCP connect {args.host}:{args.control_port} ...")
        tcp = socket.create_connection((args.host, args.control_port), timeout=args.timeout)
    except OSError as exc:
        print(f"FAIL tcp: {exc}")
        print("Hint: this board must run a PS-side TCP JSON server on port 9000.")
        return 1

    with tcp, tcp.makefile("rb") as reader:
        tcp.settimeout(args.timeout)
        request_id = 1
        try:
            hello_udp: dict[str, Any] = {
                "iq_port": args.iq_port,
                "psd_port": args.psd_port,
                "status_port": args.status_port,
            }
            if args.destination_ip:
                hello_udp["destination_ip"] = args.destination_ip

            hello = _request(
                tcp,
                reader,
                request_id,
                "hello",
                protocol_version=1,
                client_name="network-probe",
                udp=hello_udp,
            )
            _print_json_summary("hello", hello)
            request_id += 1

            ping = _request(tcp, reader, request_id, "ping", client_time_ms=0)
            _print_json_summary("ping", ping)
            request_id += 1

            if not args.skip_status:
                data, addr = _recv(status_sock, "status", args.timeout)
                print(f"OK status UDP: {len(data)} bytes from {addr[0]}:{addr[1]}")

            if not args.skip_rx:
                rx = _request(
                    tcp,
                    reader,
                    request_id,
                    "set_rx",
                    stream_id=0,
                    adc_channel=args.adc_channel,
                    frequency_hz=args.frequency_hz,
                    mode=args.mode,
                    iq_sample_rate_hz=args.iq_rate,
                    bandwidth_hz=args.bandwidth_hz,
                    sample_format="SC16_LE",
                    enable=True,
                )
                _print_json_summary("set_rx", rx)
                request_id += 1

                data, addr = _recv(iq_sock, "IQ", args.timeout)
                header = SdrIqHeader.unpack(data[:IQ_HEADER_SIZE])
                print(
                    "OK IQ UDP: "
                    f"{len(data)} bytes from {addr[0]}:{addr[1]} "
                    f"seq={header.seq} samples={header.sample_count} "
                    f"rate={header.iq_sample_rate_hz} payload={header.payload_bytes}"
                )

            if not args.skip_psd:
                psd = _request(
                    tcp,
                    reader,
                    request_id,
                    "set_psd",
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
                _print_json_summary("set_psd", psd)
                request_id += 1

                data, addr = _recv(psd_sock, "PSD", args.timeout)
                header = SdrPsdHeader.unpack(data[:PSD_HEADER_SIZE])
                print(
                    "OK PSD UDP: "
                    f"{len(data)} bytes from {addr[0]}:{addr[1]} "
                    f"frame={header.frame_seq} segment="
                    f"{header.segment_index + 1}/{header.segment_count} "
                    f"bins={header.bin_count}/{header.total_bins}"
                )

            _request(tcp, reader, request_id, "stop_all")
            print("OK stop_all")
            return 0
        except (OSError, ValueError, ProbeError) as exc:
            print(f"FAIL probe: {exc}")
            return 1
    return 0


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Probe AC920 SDR network protocol v1")
    parser.add_argument("host", help="AC920 PS IP address or hostname")
    parser.add_argument("--control-port", type=int, default=9000)
    parser.add_argument("--bind-host", default="0.0.0.0", help="local UDP bind host")
    parser.add_argument("--destination-ip", default=None, help="explicit UDP destination IP")
    parser.add_argument("--iq-port", type=int, default=9001)
    parser.add_argument("--psd-port", type=int, default=9002)
    parser.add_argument("--status-port", type=int, default=9003)
    parser.add_argument("--timeout", type=float, default=3.0)
    parser.add_argument("--skip-rx", action="store_true")
    parser.add_argument("--skip-psd", action="store_true")
    parser.add_argument("--skip-status", action="store_true")
    parser.add_argument("--adc-channel", type=int, default=0)
    parser.add_argument("--frequency-hz", type=int, default=98_500_000)
    parser.add_argument("--iq-rate", type=int, default=1_000_000)
    parser.add_argument("--bandwidth-hz", type=int, default=250_000)
    parser.add_argument("--mode", default="WFM")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    return run_probe(parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
