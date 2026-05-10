"""Backend configuration loading."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(slots=True)
class DeviceConfig:
    host: str = "127.0.0.1"
    control_port: int = 9000
    raw_capture_port: int = 9004
    client_name: str = "rpi-sdr-backend"


@dataclass(slots=True)
class UdpConfig:
    bind_host: str = "0.0.0.0"
    iq_port: int = 9001
    psd_port: int = 9002
    status_port: int = 9003


@dataclass(slots=True)
class FrontendConfig:
    attenuator_db: int = 10
    lna: str = "bypass"
    filter: str = "LPF_108M"


@dataclass(slots=True)
class RxConfig:
    stream_id: int = 0
    adc_channel: int = 0
    frequency_hz: int = 98_500_000
    mode: str = "WFM"
    iq_sample_rate_hz: int = 1_000_000
    bandwidth_hz: int = 250_000
    sample_format: str = "SC16_LE"
    enable: bool = True


@dataclass(slots=True)
class PsdConfig:
    psd_id: int = 0
    source: str = "adc0"
    enable: bool = True
    start_frequency_hz: int = 500_000
    stop_frequency_hz: int = 108_000_000
    fft_size: int = 16_384
    output_bins: int = 4096
    fps: int = 10
    sample_format: str = "I16_DBFS_Q8"


@dataclass(slots=True)
class DspConfig:
    audio_sample_rate_hz: int = 48_000
    audio_frame_ms: int = 20
    fft_size: int = 2048
    wfm_deemphasis_us: float = 50.0
    squelch_db: float = -80.0


@dataclass(slots=True)
class WebConfig:
    host: str = "0.0.0.0"
    port: int = 8080


@dataclass(slots=True)
class AppConfig:
    device: DeviceConfig = field(default_factory=DeviceConfig)
    udp: UdpConfig = field(default_factory=UdpConfig)
    frontend: FrontendConfig = field(default_factory=FrontendConfig)
    rx: RxConfig = field(default_factory=RxConfig)
    psd: PsdConfig = field(default_factory=PsdConfig)
    dsp: DspConfig = field(default_factory=DspConfig)
    web: WebConfig = field(default_factory=WebConfig)


def _merge_dataclass(instance: Any, values: dict[str, Any]) -> Any:
    for key, value in values.items():
        if hasattr(instance, key):
            setattr(instance, key, value)
    return instance


def load_config(path: str | Path | None = None) -> AppConfig:
    config = AppConfig()
    if path is None:
        return config
    path = Path(path)
    if not path.exists():
        return config
    try:
        import yaml
    except ImportError as exc:
        raise RuntimeError("PyYAML is required to load YAML config files") from exc
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise ValueError("config file must contain a mapping")
    for section_name, section in (
        ("device", config.device),
        ("udp", config.udp),
        ("frontend", config.frontend),
        ("rx", config.rx),
        ("psd", config.psd),
        ("dsp", config.dsp),
        ("web", config.web),
    ):
        values = data.get(section_name)
        if isinstance(values, dict):
            _merge_dataclass(section, values)
    return config
