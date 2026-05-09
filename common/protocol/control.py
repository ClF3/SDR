"""JSON Lines control protocol helpers."""

from __future__ import annotations

import json
from typing import Any

ERROR_CODES = {
    "invalid_json",
    "unsupported_version",
    "invalid_command",
    "invalid_field",
    "out_of_range",
    "busy",
    "hardware_fault",
    "timeout",
    "internal_error",
}


class JsonLineError(ValueError):
    """Raised when a JSON Lines control message is invalid."""


def encode_json_line(message: dict[str, Any]) -> bytes:
    return (json.dumps(message, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def decode_json_line(line: bytes | str) -> dict[str, Any]:
    if isinstance(line, bytes):
        line = line.decode("utf-8")
    try:
        value = json.loads(line)
    except json.JSONDecodeError as exc:
        raise JsonLineError("invalid JSON line") from exc
    if not isinstance(value, dict):
        raise JsonLineError("JSON line must contain an object")
    return value


def build_request(request_id: int, cmd: str, **fields: Any) -> dict[str, Any]:
    return {"request_id": request_id, "cmd": cmd, **fields}


def build_response(request_id: int | None, ok: bool = True, **fields: Any) -> dict[str, Any]:
    message: dict[str, Any] = {"ok": ok, **fields}
    if request_id is not None:
        message = {"request_id": request_id, **message}
    return message


def build_error(
    request_id: int | None,
    code: str,
    message: str,
    **fields: Any,
) -> dict[str, Any]:
    if code not in ERROR_CODES:
        code = "internal_error"
    return build_response(
        request_id,
        ok=False,
        error={"code": code, "message": message, **fields},
    )

