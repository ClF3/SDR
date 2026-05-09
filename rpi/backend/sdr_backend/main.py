"""Command line entrypoint for the Raspberry Pi backend."""

from __future__ import annotations

import argparse

from .app import create_app
from .config import load_config


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Raspberry Pi WebSDR backend")
    parser.add_argument("--config", default="rpi/backend/config/dev.yaml")
    parser.add_argument("--host", default=None, help="override web bind host")
    parser.add_argument("--port", type=int, default=None, help="override web port")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config = load_config(args.config)
    if args.host:
        config.web.host = args.host
    if args.port:
        config.web.port = args.port
    try:
        import uvicorn
    except ImportError as exc:
        raise RuntimeError("uvicorn is required to run the backend service") from exc
    uvicorn.run(create_app(config), host=config.web.host, port=config.web.port)

