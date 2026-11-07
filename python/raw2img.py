#!/usr/bin/env python3
import sys
from pathlib import Path
from PIL import Image


def usage() -> None:
    print("Usage: python raw2img.py <input.raw> [output.png]")
    print("       If <output.png> is omitted, the result is written next to")
    print("       the input file with the .png extension.")


def main() -> None:
    if len(sys.argv) not in (2, 3):
        usage()
        sys.exit(1)

    raw_file = Path(sys.argv[1])
    if not raw_file.is_file():
        sys.exit(f"Error: file not found — {raw_file}")

    if len(sys.argv) == 3:
        out_file = Path(sys.argv[2])
    else:
        out_file = raw_file.with_suffix(".png")

    w, h = 640, 480

    img_data = raw_file.read_bytes()

    expected_size = w * h * 3
    if len(img_data) != expected_size:
        print(f"WARNING: File size mismatch! Expected {expected_size} bytes, "
              f"got {len(img_data)} bytes.")
        print("Возможно, valid_o выдал другое количество пикселей.")
        # Обрезаем/дополняем, чтобы PIL не упал
        if len(img_data) > expected_size:
            img_data = img_data[:expected_size]
        else:
            img_data = img_data + b"\x00" * (expected_size - len(img_data))

    img = Image.frombytes("RGB", (w, h), img_data)

    # Создаём родительскую папку, если её нет
    out_file.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_file)

    print(f"Successfully saved {out_file} ({w}x{h})")


if __name__ == "__main__":
    main()
