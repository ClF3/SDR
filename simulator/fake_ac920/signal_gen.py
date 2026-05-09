"""Synthetic IQ generators for fake AC920."""

from __future__ import annotations

from dataclasses import dataclass
import math
import random


@dataclass(slots=True)
class ComplexOscillator:
    sample_rate_hz: int
    phase: float = 0.0
    audio_phase: float = 0.0

    def _step_audio(self, freq_hz: float, count: int) -> list[float]:
        step = 2.0 * math.pi * freq_hz / self.sample_rate_hz
        values = []
        phase = self.audio_phase
        for _ in range(count):
            values.append(math.sin(phase))
            phase += step
            if phase > math.tau:
                phase -= math.tau
        self.audio_phase = phase
        return values

    def make_iq(self, scenario: str, count: int) -> list[complex]:
        scenario = scenario.lower()
        if scenario == "noise":
            return [
                complex(random.uniform(-0.25, 0.25), random.uniform(-0.25, 0.25))
                for _ in range(count)
            ]

        if scenario == "tone":
            return self._complex_tone(10_000.0, count, amplitude=0.55)

        tone = self._step_audio(1_000.0, count)

        if scenario == "am_tone":
            return [complex(0.25 + 0.45 * (0.5 + 0.5 * x), 0.0) for x in tone]

        if scenario == "ssb_tone":
            return self._complex_tone(1_000.0, count, amplitude=0.55)

        if scenario == "nfm_tone":
            return self._phase_modulated(tone, beta=0.8)

        if scenario == "wfm_tone":
            return self._phase_modulated(tone, beta=5.0)

        return self._complex_tone(1_000.0, count, amplitude=0.4)

    def _complex_tone(self, freq_hz: float, count: int, amplitude: float) -> list[complex]:
        step = 2.0 * math.pi * freq_hz / self.sample_rate_hz
        out = []
        phase = self.phase
        for _ in range(count):
            out.append(complex(math.cos(phase) * amplitude, math.sin(phase) * amplitude))
            phase += step
            if phase > math.tau:
                phase -= math.tau
        self.phase = phase
        return out

    def _phase_modulated(self, audio: list[float], beta: float) -> list[complex]:
        out = []
        phase = self.phase
        for value in audio:
            phase += beta * value / max(self.sample_rate_hz / 48_000.0, 1.0)
            if phase > math.tau:
                phase -= math.tau
            elif phase < -math.tau:
                phase += math.tau
            out.append(complex(math.cos(phase) * 0.55, math.sin(phase) * 0.55))
        self.phase = phase
        return out


def complex_to_sc16(iq: list[complex]) -> bytes:
    payload = bytearray(len(iq) * 4)
    idx = 0
    for sample in iq:
        i_val = max(-32768, min(32767, int(sample.real * 32767.0)))
        q_val = max(-32768, min(32767, int(sample.imag * 32767.0)))
        payload[idx : idx + 2] = int(i_val).to_bytes(2, "little", signed=True)
        payload[idx + 2 : idx + 4] = int(q_val).to_bytes(2, "little", signed=True)
        idx += 4
    return bytes(payload)

