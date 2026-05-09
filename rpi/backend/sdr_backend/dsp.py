"""Streaming demodulation helpers for first WebSDR bring-up."""

from __future__ import annotations

import math


class DspUnavailable(RuntimeError):
    pass


def _require_numpy():
    try:
        import numpy as np
    except ImportError as exc:
        raise DspUnavailable("NumPy is required for DSP processing") from exc
    return np


class Demodulator:
    def __init__(
        self,
        audio_sample_rate_hz: int = 48_000,
        audio_frame_ms: int = 20,
        wfm_deemphasis_us: float = 50.0,
    ) -> None:
        self.audio_sample_rate_hz = audio_sample_rate_hz
        self.frame_samples = int(audio_sample_rate_hz * audio_frame_ms / 1000)
        self.wfm_deemphasis_us = wfm_deemphasis_us
        self._mode = "WFM"
        self._input_rate = 1_000_000
        self._tail = None
        self._last_iq = None
        self._cw_phase = 0.0
        self._deemph_last = 0.0

    def configure(self, mode: str, input_rate_hz: int) -> None:
        mode = mode.upper()
        if mode != self._mode or input_rate_hz != self._input_rate:
            self._tail = None
            self._last_iq = None
            self._cw_phase = 0.0
            self._deemph_last = 0.0
        self._mode = mode
        self._input_rate = input_rate_hz

    def process_sc16(self, payload: bytes) -> list[bytes]:
        np = _require_numpy()
        if not payload:
            return []
        raw = np.frombuffer(payload, dtype="<i2")
        if raw.size < 2:
            return []
        raw = raw[: raw.size - (raw.size % 2)]
        pairs = raw.reshape((-1, 2)).astype(np.float32) / 32768.0
        iq = pairs[:, 0] + 1j * pairs[:, 1]
        audio = self._demodulate(iq)
        audio = self._resample(audio, self._input_rate, self.audio_sample_rate_hz)
        if self._mode == "WFM":
            audio = self._deemphasis(audio)
        audio = self._condition_audio(audio)
        return self._frame_pcm(audio)

    def _demodulate(self, iq):
        np = _require_numpy()
        mode = self._mode
        if mode == "AM":
            audio = np.abs(iq)
        elif mode == "LSB":
            audio = np.real(np.conjugate(iq))
        elif mode in ("USB", "SSB", "IQ"):
            audio = np.real(iq)
        elif mode == "CW":
            n = np.arange(iq.size, dtype=np.float32)
            step = 2.0 * math.pi * 700.0 / self._input_rate
            osc = np.exp(1j * (self._cw_phase + step * n))
            self._cw_phase = (self._cw_phase + step * iq.size) % math.tau
            audio = np.real(iq * osc)
        elif mode in ("NFM", "WFM"):
            if self._last_iq is not None:
                iq2 = np.concatenate(([self._last_iq], iq))
            else:
                iq2 = iq
            self._last_iq = iq[-1]
            if iq2.size < 2:
                return np.zeros(0, dtype=np.float32)
            audio = np.angle(iq2[1:] * np.conjugate(iq2[:-1]))
        else:
            audio = np.real(iq)
        return np.asarray(audio, dtype=np.float32)

    def _resample(self, data, in_rate: int, out_rate: int):
        np = _require_numpy()
        if data.size == 0 or in_rate == out_rate:
            return data.astype(np.float32, copy=False)
        try:
            from scipy.signal import resample_poly

            gcd = math.gcd(in_rate, out_rate)
            return resample_poly(data, out_rate // gcd, in_rate // gcd).astype(np.float32)
        except ImportError:
            duration = data.size / float(in_rate)
            out_count = max(1, int(duration * out_rate))
            x_old = np.linspace(0.0, duration, num=data.size, endpoint=False)
            x_new = np.linspace(0.0, duration, num=out_count, endpoint=False)
            return np.interp(x_new, x_old, data).astype(np.float32)

    def _deemphasis(self, data):
        np = _require_numpy()
        if data.size == 0:
            return data
        tau = self.wfm_deemphasis_us * 1e-6
        dt = 1.0 / self.audio_sample_rate_hz
        alpha = dt / (tau + dt)
        out = np.empty_like(data, dtype=np.float32)
        last = self._deemph_last
        for idx, sample in enumerate(data):
            last = last + alpha * (float(sample) - last)
            out[idx] = last
        self._deemph_last = last
        return out

    def _condition_audio(self, data):
        np = _require_numpy()
        if data.size == 0:
            return data.astype(np.float32)
        data = data.astype(np.float32, copy=False)
        data = data - float(np.mean(data))
        rms = float(np.sqrt(np.mean(data * data))) if data.size else 0.0
        if rms > 1e-5:
            data = data * min(8.0, 0.18 / rms)
        return np.clip(data, -0.95, 0.95)

    def _frame_pcm(self, audio) -> list[bytes]:
        np = _require_numpy()
        if self._tail is not None and self._tail.size:
            audio = np.concatenate((self._tail, audio))
        frames = []
        offset = 0
        while offset + self.frame_samples <= audio.size:
            chunk = audio[offset : offset + self.frame_samples]
            pcm = np.asarray(chunk * 32767.0, dtype="<i2").tobytes()
            frames.append(pcm)
            offset += self.frame_samples
        self._tail = audio[offset:].copy()
        return frames

