from __future__ import annotations

import importlib.util
import math
import unittest

from rpi.backend.sdr_backend.dsp import Demodulator
from simulator.fake_ac920.signal_gen import ComplexOscillator, complex_to_sc16


@unittest.skipIf(importlib.util.find_spec("numpy") is None, "NumPy is not installed")
class DspOptionalTests(unittest.TestCase):
    def _dominant_frequency(self, pcm: bytes, sample_rate: int) -> float:
        import numpy as np

        audio = np.frombuffer(pcm, dtype="<i2").astype(np.float32)
        window = np.hanning(audio.size)
        spectrum = np.fft.rfft(audio * window)
        freqs = np.fft.rfftfreq(audio.size, d=1.0 / sample_rate)
        index = int(np.argmax(np.abs(spectrum[1:])) + 1)
        return float(freqs[index])

    def test_am_tone_demodulates_near_1khz(self) -> None:
        sample_rate = 250_000
        osc = ComplexOscillator(sample_rate)
        demod = Demodulator(audio_sample_rate_hz=48_000)
        demod.configure("AM", sample_rate)
        frames: list[bytes] = []
        for _ in range(600):
            payload = complex_to_sc16(osc.make_iq("am_tone", 256))
            frames.extend(demod.process_sc16(payload))
        pcm = b"".join(frames)
        self.assertGreater(len(pcm), 48_000)
        freq = self._dominant_frequency(pcm[: 48_000 * 2], 48_000)
        self.assertTrue(math.isclose(freq, 1000.0, abs_tol=80.0), freq)


if __name__ == "__main__":
    unittest.main()
