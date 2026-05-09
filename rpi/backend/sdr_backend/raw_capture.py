"""TCP raw ADC capture helper."""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

from common.protocol import build_request, decode_json_line, encode_json_line


async def capture_raw(
    host: str,
    port: int,
    adc_channel: int,
    sample_count: int,
    output_path: str | Path,
) -> dict[str, Any]:
    reader, writer = await asyncio.open_connection(host, port)
    request = build_request(
        1,
        "capture_raw",
        adc_channel=adc_channel,
        sample_count=sample_count,
        sample_format="S16_LE",
    )
    writer.write(encode_json_line(request))
    await writer.drain()
    line = await asyncio.wait_for(reader.readline(), timeout=5.0)
    response = decode_json_line(line)
    if not response.get("ok"):
        writer.close()
        await writer.wait_closed()
        raise RuntimeError(response.get("error", {}).get("message", "raw capture failed"))
    payload_bytes = int(response["payload_bytes"])
    payload = await asyncio.wait_for(reader.readexactly(payload_bytes), timeout=10.0)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(payload)
    writer.close()
    await writer.wait_closed()
    return {**response, "path": str(output_path)}

