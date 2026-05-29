#!/usr/bin/env python3
import argparse
import math
from pathlib import Path


def twos(value: int, width: int) -> int:
    mask = (1 << width) - 1
    return value & mask


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate simple ADC stimulus vectors.")
    parser.add_argument("--out-dir", default="fpga/sim/vectors")
    parser.add_argument("--fs", type=float, default=250e6)
    parser.add_argument("--samples", type=int, default=4096)
    parser.add_argument("--width", type=int, default=14)
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    tones = [
        ("tone_1mhz.hex", 1e6),
        ("tone_10mhz.hex", 10e6),
        ("tone_98p5mhz.hex", 98.5e6),
    ]

    amp = int((1 << (args.width - 1)) * 0.65)
    for name, freq in tones:
        path = out_dir / name
        with path.open("w", encoding="ascii") as f:
            for n in range(args.samples):
                value = round(amp * math.sin(2 * math.pi * freq * n / args.fs))
                f.write(f"{twos(value, args.width):0{(args.width + 3) // 4}x}\n")

    with (out_dir / "impulse.hex").open("w", encoding="ascii") as f:
        for n in range(args.samples):
            value = amp if n == 0 else 0
            f.write(f"{twos(value, args.width):0{(args.width + 3) // 4}x}\n")


if __name__ == "__main__":
    main()
