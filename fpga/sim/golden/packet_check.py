#!/usr/bin/env python3
import struct
import sys


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: packet_check.py packet_words.bin")
        raise SystemExit(2)

    data = open(sys.argv[1], "rb").read()
    words = struct.unpack("<" + "I" * (len(data) // 4), data[: len(data) // 4 * 4])
    if not words or words[0] != 0x53445231:
        print("bad magic")
        raise SystemExit(1)
    print(f"magic=0x{words[0]:08x} words={len(words)} seq={words[3] if len(words) > 3 else 'n/a'}")


if __name__ == "__main__":
    main()
