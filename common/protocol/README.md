# Protocol

Shared protocol definitions used by the fake AC920 simulator, Raspberry Pi
backend, and tests.

The source of truth for the wire interface is still
`docs/network_protocol.md`; the Python helpers here implement that document:

- `packets.py`: binary little-endian IQ/PSD UDP headers
- `control.py`: TCP JSON Lines request/response helpers

