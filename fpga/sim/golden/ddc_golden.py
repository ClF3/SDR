#!/usr/bin/env python3
import argparse
import math


def freq_word(freq_hz: float, fs_hz: float = 250e6, phase_width: int = 32) -> int:
    return round(freq_hz / fs_hz * (1 << phase_width)) & ((1 << phase_width) - 1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Print useful DDC reference values.")
    parser.add_argument("freq_hz", type=float)
    parser.add_argument("--fs", type=float, default=250e6)
    parser.add_argument("--decim", type=int, default=1000)
    args = parser.parse_args()

    word = freq_word(args.freq_hz, args.fs)
    out_rate = args.fs / args.decim
    cic_gain = args.decim ** 3
    gain_shift = math.ceil(math.log2(cic_gain))

    print(f"freq_word_dec={word}")
    print(f"freq_word_hex=0x{word:08x}")
    print(f"iq_sample_rate_hz={out_rate:.3f}")
    print(f"recommended_gain_shift={gain_shift}")


if __name__ == "__main__":
    main()
