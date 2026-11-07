#!/usr/bin/env python3
"""
img2raw.py — Converts an image (JPG/PNG) to raw RGB byte stream
for use as SystemVerilog testbench stimulus.

Output: flat binary file, pixel-by-pixel, row-by-row (top to bottom, left to right).
Each pixel = 3 bytes: [R, G, B].

Usage:
    python img2raw.py input.png
    python img2raw.py input.jpg -o frame.raw
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required. Install it with:  pip install Pillow")


def convert_to_raw(input_path: Path, output_path: Path | None = None) -> None:
    img = Image.open(input_path)

    # Convert to RGB (handles RGBA, grayscale, palette, etc.)
    img = img.convert("RGB")
    width, height = img.size

    # .tobytes() returns row-major flat bytes: R G B R G B ...
    raw_data = img.tobytes()

    if output_path is None:
        output_path = input_path.with_suffix(".raw")

    output_path.write_bytes(raw_data)

    print(f"Input:   {input_path}  ({width}x{height}, {img.mode})")
    print(f"Output:  {output_path}  ({len(raw_data)} bytes)")
    print(f"Params:  WIDTH={width}  HEIGHT={height}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert an image to raw RGB for SV testbench"
    )
    parser.add_argument("input", type=Path, help="Path to input image (JPG/PNG)")
    parser.add_argument("-o", "--output", type=Path, default=None, help="Output .raw file path")
    args = parser.parse_args()

    if not args.input.is_file():
        sys.exit(f"Error: file not found — {args.input}")

    convert_to_raw(args.input, args.output)


if __name__ == "__main__":
    main()
