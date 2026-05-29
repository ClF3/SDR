#!/usr/bin/env python3
import argparse
import math


def main() -> None:
    parser = argparse.ArgumentParser(description="Estimate CIC gain and output rate.")
    parser.add_argument("--decim", type=int, required=True)
    parser.add_argument("--stages", type=int, default=3)
    parser.add_argument("--fs", type=float, default=250e6)
    args = parser.parse_args()

    gain = args.decim ** args.stages
    print(f"output_rate_hz={args.fs / args.decim:.3f}")
    print(f"cic_gain={gain}")
    print(f"gain_bits={math.ceil(math.log2(gain))}")


if __name__ == "__main__":
    main()
