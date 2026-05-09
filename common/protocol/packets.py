"""Binary UDP packet definitions shared by fake AC920 and Raspberry Pi backend."""

from __future__ import annotations

from dataclasses import dataclass
import struct

SDR_PROTOCOL_VERSION = 1

SDR_IQ_MAGIC = 0x51494453
SDR_PSD_MAGIC = 0x53504453

SDR_FRAME_IQ = 1
SDR_FRAME_PSD = 2

SDR_SAMPLE_SC16_LE = 1
SDR_PSD_I16_DBFS_Q8 = 1

SDR_IQ_FLAG_ADC_OR = 1 << 0
SDR_IQ_FLAG_FIFO_OVERFLOW = 1 << 1
SDR_IQ_FLAG_DISCONTINUITY = 1 << 2
SDR_IQ_FLAG_CONFIG_CHANGED = 1 << 3

SDR_PSD_FLAG_DISCONTINUITY = 1 << 0
SDR_PSD_FLAG_CONFIG_CHANGED = 1 << 1
SDR_PSD_FLAG_OVERFLOW = 1 << 2

_IQ_STRUCT = struct.Struct("<IHHHHIQQIIHHHhIIQ")
_PSD_STRUCT = struct.Struct("<IHHHHIQQQIHHHHHHHHIQ")

IQ_HEADER_SIZE = _IQ_STRUCT.size
PSD_HEADER_SIZE = _PSD_STRUCT.size


class PacketError(ValueError):
    """Raised when a binary packet is malformed."""


@dataclass(slots=True)
class SdrIqHeader:
    magic: int = SDR_IQ_MAGIC
    version: int = SDR_PROTOCOL_VERSION
    header_len: int = IQ_HEADER_SIZE
    frame_type: int = SDR_FRAME_IQ
    stream_id: int = 0
    seq: int = 0
    adc_timestamp: int = 0
    frequency_hz: int = 0
    iq_sample_rate_hz: int = 250_000
    bandwidth_hz: int = 12_000
    sample_format: int = SDR_SAMPLE_SC16_LE
    sample_count: int = 0
    flags: int = 0
    gain_db_q8: int = 0
    decimation: int = 1000
    payload_bytes: int = 0
    reserved0: int = 0

    def pack(self) -> bytes:
        self.validate()
        return _IQ_STRUCT.pack(
            self.magic,
            self.version,
            self.header_len,
            self.frame_type,
            self.stream_id,
            self.seq,
            self.adc_timestamp,
            self.frequency_hz,
            self.iq_sample_rate_hz,
            self.bandwidth_hz,
            self.sample_format,
            self.sample_count,
            self.flags,
            self.gain_db_q8,
            self.decimation,
            self.payload_bytes,
            self.reserved0,
        )

    @classmethod
    def unpack(cls, data: bytes | bytearray | memoryview) -> "SdrIqHeader":
        if len(data) < IQ_HEADER_SIZE:
            raise PacketError(f"IQ packet too short for header: {len(data)} bytes")
        values = _IQ_STRUCT.unpack_from(data)
        header = cls(*values)
        header.validate()
        return header

    def validate(self) -> None:
        if self.magic != SDR_IQ_MAGIC:
            raise PacketError(f"bad IQ magic 0x{self.magic:08x}")
        if self.version != SDR_PROTOCOL_VERSION:
            raise PacketError(f"unsupported IQ protocol version {self.version}")
        if self.header_len != IQ_HEADER_SIZE:
            raise PacketError(f"bad IQ header length {self.header_len}")
        if self.frame_type != SDR_FRAME_IQ:
            raise PacketError(f"bad IQ frame type {self.frame_type}")
        if self.sample_format != SDR_SAMPLE_SC16_LE:
            raise PacketError(f"unsupported IQ sample format {self.sample_format}")
        expected_payload = self.sample_count * 4
        if self.payload_bytes != expected_payload:
            raise PacketError(
                f"IQ payload_bytes {self.payload_bytes} != sample_count * 4 {expected_payload}"
            )

    @property
    def next_timestamp_delta(self) -> int:
        return self.decimation * self.sample_count


@dataclass(slots=True)
class SdrPsdHeader:
    magic: int = SDR_PSD_MAGIC
    version: int = SDR_PROTOCOL_VERSION
    header_len: int = PSD_HEADER_SIZE
    frame_type: int = SDR_FRAME_PSD
    psd_id: int = 0
    frame_seq: int = 0
    adc_timestamp: int = 0
    start_frequency_hz: int = 0
    bin_spacing_millihz: int = 0
    fft_size: int = 0
    total_bins: int = 0
    segment_index: int = 0
    segment_count: int = 0
    bin_start: int = 0
    bin_count: int = 0
    sample_format: int = SDR_PSD_I16_DBFS_Q8
    flags: int = 0
    averaging_count: int = 1
    payload_bytes: int = 0
    reserved0: int = 0

    def pack(self) -> bytes:
        self.validate()
        return _PSD_STRUCT.pack(
            self.magic,
            self.version,
            self.header_len,
            self.frame_type,
            self.psd_id,
            self.frame_seq,
            self.adc_timestamp,
            self.start_frequency_hz,
            self.bin_spacing_millihz,
            self.fft_size,
            self.total_bins,
            self.segment_index,
            self.segment_count,
            self.bin_start,
            self.bin_count,
            self.sample_format,
            self.flags,
            self.averaging_count,
            self.payload_bytes,
            self.reserved0,
        )

    @classmethod
    def unpack(cls, data: bytes | bytearray | memoryview) -> "SdrPsdHeader":
        if len(data) < PSD_HEADER_SIZE:
            raise PacketError(f"PSD packet too short for header: {len(data)} bytes")
        values = _PSD_STRUCT.unpack_from(data)
        header = cls(*values)
        header.validate()
        return header

    def validate(self) -> None:
        if self.magic != SDR_PSD_MAGIC:
            raise PacketError(f"bad PSD magic 0x{self.magic:08x}")
        if self.version != SDR_PROTOCOL_VERSION:
            raise PacketError(f"unsupported PSD protocol version {self.version}")
        if self.header_len != PSD_HEADER_SIZE:
            raise PacketError(f"bad PSD header length {self.header_len}")
        if self.frame_type != SDR_FRAME_PSD:
            raise PacketError(f"bad PSD frame type {self.frame_type}")
        if self.sample_format != SDR_PSD_I16_DBFS_Q8:
            raise PacketError(f"unsupported PSD sample format {self.sample_format}")
        expected_payload = self.bin_count * 2
        if self.payload_bytes != expected_payload:
            raise PacketError(
                f"PSD payload_bytes {self.payload_bytes} != bin_count * 2 {expected_payload}"
            )

