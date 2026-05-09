from __future__ import annotations

import unittest

from common.protocol import build_error, build_request, decode_json_line, encode_json_line


class ControlJsonTests(unittest.TestCase):
    def test_json_line_round_trip(self) -> None:
        request = build_request(1, "ping", client_time_ms=123)
        encoded = encode_json_line(request)
        self.assertTrue(encoded.endswith(b"\n"))
        decoded = decode_json_line(encoded)
        self.assertEqual(decoded["request_id"], 1)
        self.assertEqual(decoded["cmd"], "ping")

    def test_error_code_fallback(self) -> None:
        error = build_error(2, "not_a_code", "boom")
        self.assertFalse(error["ok"])
        self.assertEqual(error["error"]["code"], "internal_error")


if __name__ == "__main__":
    unittest.main()

