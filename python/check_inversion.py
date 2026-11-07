#!/usr/bin/env python3
"""
Проверяет, что изображение B является горизонтальной инверсией изображения A:
    B[y][x] == A[y][W-1-x]   для всех x, y

Поддерживает:
  * .raw RGB24 / BGR24 (по умолчанию 640x480x3)
  * .png / .jpg / .bmp через PIL (если установлен)

Примеры:
    # RAW: сравнить input.raw и output.raw (640x480, RGB, 3 байта на пиксель)
    python3 python/check_inversion.py images/lemme_chex.raw images/lemme_chex_inv.raw

    # Другой размер
    python3 python/check_inversion.py a.raw b.raw --width 1920 --height 1080

    # PNG/JPG
    python3 python/check_inversion.py in.png out.png

Exit code: 0 — PASS, 1 — FAIL, 2 — ошибка входных данных.
"""

import argparse
import os
import sys

import numpy as np


# ---------------------------------------------------------------------
# Загрузка изображения
# ---------------------------------------------------------------------
def load_raw(path: str, width: int, height: int, channels: int,
             dtype=np.uint8) -> np.ndarray:
    """Читает .raw и возвращает массив [H, W, C]."""
    expected = width * height * channels * np.dtype(dtype).itemsize
    actual = os.path.getsize(path)
    if actual != expected:
        print(f"WARN: {path}: размер {actual} байт, ожидалось {expected} "
              f"({width}x{height}x{channels} x {np.dtype(dtype).itemsize} байт). "
              f"Читаю сколько есть и дополняю нулями.", file=sys.stderr)

    buf = np.fromfile(path, dtype=dtype)
    if buf.size < width * height * channels:
        pad = width * height * channels - buf.size
        buf = np.concatenate([buf, np.zeros(pad, dtype=dtype)])
    else:
        buf = buf[:width * height * channels]

    return buf.reshape(height, width, channels)


def load_image(path: str, width: int | None, height: int | None,
               channels: int) -> np.ndarray:
    """Загружает либо .raw, либо обычную картинку через PIL."""
    ext = os.path.splitext(path)[1].lower()
    if ext == ".raw":
        if width is None or height is None:
            raise ValueError(
                f"Для .raw нужно указать --width и --height (файл {path})")
        return load_raw(path, width, height, channels)

    # Обычная картинка
    try:
        from PIL import Image
    except ImportError:
        raise RuntimeError(
            "Для чтения изображений нужен Pillow: pip install pillow")

    img = Image.open(path).convert("RGB")
    return np.asarray(img, dtype=np.uint8)


# ---------------------------------------------------------------------
# Сравнение
# ---------------------------------------------------------------------
def check_inversion(a: np.ndarray, b: np.ndarray,
                    max_report: int = 10) -> int:
    """
    Проверяет b == flip(a, axis=1).
    Возвращает 0 если совпадает, иначе количество несовпавших пикселей.
    """
    if a.shape != b.shape:
        print(f"FAIL: размеры не совпадают: A={a.shape}, B={b.shape}")
        return -1

    h, w, c = a.shape
    a_flipped = a[:, ::-1, :]          # горизонтальный флип эталона

    # Попиксельное сравнение (все каналы сразу)
    diff = np.any(a_flipped != b, axis=2)         # [H, W] bool
    n_bad = int(diff.sum())

    if n_bad == 0:
        print(f"PASS: {h}x{w}x{c} — точная горизонтальная инверсия "
              f"({h*w} пикселей)")
        return 0

    total = h * w
    print(f"FAIL: {n_bad} / {total} пикселей не совпадают "
          f"({100.0 * n_bad / total:.3f}%)")

    # Где именно
    bad_coords = np.argwhere(diff)               # [n_bad, 2] -> (y, x)
    if bad_coords.size:
        ys = bad_coords[:, 0]
        xs = bad_coords[:, 1]
        print(f"      диапазон ошибок: y=[{ys.min()}..{ys.max()}], "
              f"x=[{xs.min()}..{xs.max()}]")

        # Разбивка по строкам — чтобы сразу увидеть "потерян последний пиксель"
        per_row = diff.sum(axis=1)
        bad_rows = np.where(per_row > 0)[0]
        if bad_rows.size <= 20:
            print(f"      строки с ошибками: {bad_rows.tolist()} "
                  f"(пикселей в каждой: {per_row[bad_rows].tolist()})")
        else:
            print(f"      строк с ошибками: {bad_rows.size} "
                  f"(первые: {bad_rows[:20].tolist()})")

    # Примеры
    print(f"      первые {min(max_report, n_bad)} расхождений:")
    print("        y,  x   exp(R/G/B)  got(R/G/B)")
    for y, x in bad_coords[:max_report]:
        exp = a_flipped[y, x]
        got = b[y, x]
        print(f"        {y:>4d} {x:>4d}   "
              f"{exp[0]:02x}/{exp[1]:02x}/{exp[2]:02x}  "
              f"{got[0]:02x}/{got[1]:02x}/{got[2]:02x}")

    return n_bad


# ---------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------
def main() -> int:
    p = argparse.ArgumentParser(
        description="Проверяет, что B — точная горизонтальная инверсия A")
    p.add_argument("a", help="эталон (raw/png/jpg)")
    p.add_argument("b", help="результат, который должен быть инверсией A")
    p.add_argument("--width",  type=int, default=None,
                   help="ширина, обязательна для .raw (по умолчанию 640)")
    p.add_argument("--height", type=int, default=None,
                   help="высота, обязательна для .raw (по умолчанию 480)")
    p.add_argument("--channels", type=int, default=3,
                   help="каналов на пиксель для .raw (по умолчанию 3)")
    p.add_argument("--max-report", type=int, default=10,
                   help="сколько первых расхождений вывести (по умолчанию 10)")
    p.add_argument("--dump-diff", metavar="PATH",
                   help="сохранить diff-картинку (только для PNG/JPG)")

    args = p.parse_args()

    # Для .raw подставляем дефолты 640x480, если размеры не заданы
    is_raw = args.a.lower().endswith(".raw") or args.b.lower().endswith(".raw")
    if is_raw:
        if args.width is None:
            args.width = 640
            print(f"INFO: --width не задан, использую {args.width}")
        if args.height is None:
            args.height = 480
            print(f"INFO: --height не задан, использую {args.height}")

    try:
        a = load_image(args.a, args.width, args.height, args.channels)
        b = load_image(args.b, args.width, args.height, args.channels)
    except (OSError, ValueError, RuntimeError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    n_bad = check_inversion(a, b, max_report=args.max_report)

    # Диагностическая картинка (все несовпавшие пиксели = красные)
    if args.dump_diff:
        try:
            from PIL import Image
        except ImportError:
            print("WARN: Pillow не установлен, --dump-diff пропущен",
                  file=sys.stderr)
        else:
            diff_img = np.zeros_like(b)
            if n_bad > 0:
                mask = np.any(a[:, ::-1, :] != b, axis=2)
                diff_img[mask] = [255, 0, 0]
            Image.fromarray(diff_img).save(args.dump_diff)
            print(f"INFO: diff сохранён в {args.dump_diff}")

    return 0 if n_bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
