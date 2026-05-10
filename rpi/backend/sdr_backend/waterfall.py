"""Local FFT spectrum generation from current IQ stream."""

from __future__ import annotations


class WaterfallEngine:
    def __init__(self, fft_size: int = 2048) -> None:
        self.fft_size = fft_size
        self._buffer = bytearray()

    def compute(self, payload: bytes, center_frequency_hz: int, sample_rate_hz: int) -> dict | None:
        try:
            import numpy as np
        except ImportError:
            return None
        needed_bytes = self.fft_size * 4
        self._buffer.extend(payload)
        if len(self._buffer) < needed_bytes:
            return None
        chunk = bytes(self._buffer[:needed_bytes])
        del self._buffer[:needed_bytes]
        if len(self._buffer) > needed_bytes * 4:
            del self._buffer[:-needed_bytes]
        raw = np.frombuffer(chunk, dtype="<i2")
        pairs = raw.reshape((-1, 2)).astype(np.float32)
        iq = (pairs[:, 0] + 1j * pairs[:, 1]) / 32768.0
        window = np.hanning(iq.size).astype(np.float32)
        spec = np.fft.fftshift(np.fft.fft(iq * window))
        mag = np.abs(spec) / max(float(window.sum()), 1.0)
        dbfs = 20.0 * np.log10(np.maximum(mag, 1e-8))
        return {
            "type": "local_spectrum",
            "center_frequency_hz": center_frequency_hz,
            "sample_rate_hz": sample_rate_hz,
            "fft_size": int(iq.size),
            "bin_spacing_hz": sample_rate_hz / float(iq.size),
            "bins_dbfs": [round(float(x), 2) for x in dbfs.tolist()],
        }
