# invert_horizontal_image

Зеркалит каждую строку изображения по горизонтали. Пиксели идут потоком через AXI-Stream-подобный интерфейс, в памяти живёт одна строка (`line_buf`), направление обхода меняется через строку — получается реверс.

## Структура

```
rtl/src/inv_horiz_img.sv   — сам модуль
rtl/headers/img_pkg.svh    — pixel_t {R,G,B}, по 8 бит на канал
tb/tb_top.sv               — тестбенч
python/                    — утилиты
images/                    — картинки
Makefile
```

## Модуль

Интерфейс — два потока, `s_*` на вход, `m_*` на выход (`tvalid`/`tready`/`tdata`, у выхода ещё `m_tlast`). Параметры — `IMG_WIDTH`, `IMG_HEIGHT`. Внутри три состояния обхода (`FWD`/`BACK`/`STAY`), `m_tlast` поднимается на последнем пикселе кадра, после чего состояние сбрасывается.

`s_tready` напрямую завязан на `m_tready` — входного FIFO нет, источник должен уметь держать пиксель, пока приёмник не готов.

## Запуск

Нужен Verilator 5.x (с `--binary`), Python 3, numpy.

```bash
make prepare              # jpg -> images/lemme_chex.raw, один раз
make sim                  # сборка
make run                  # прогон
make wave                 # gtkwave с build/wave.vcd
```

Пути к файлам задаются через plusargs:

```bash
make run IN=images/foo.raw OUT=images/foo_inv.raw
```

По умолчанию `run` берёт `images/lemme_chex.raw` и пишет `images/lemme_chex_inv.raw`. Сборка и запуск специально разведены: `sim` не требует наличия `.raw`, `run` не пересобирает.

## Утилиты

**img2raw.py** — jpg/png → raw RGB24, порядок R,G,B, 3 байта на пиксель.

```bash
python3 python/img2raw.py images/lemme_chex.jpg -o images/lemme_chex.raw
```

**raw2img.py** — raw → png, чтобы посмотреть глазами. Размер по умолчанию 640×480.

```bash
python3 python/raw2img.py images/lemme_chex_inv.raw
python3 python/raw2img.py images/lemme_chex_inv.raw out.png
```

**check_inversion.py** — проверяет, что второй файл — точная горизонтальная инверсия первого. Exit code 0/1/2 (OK / различия / ошибка чтения). При расхождениях печатает координаты первых несовпадений и разбивку по строкам — по этому паттерну сразу видно, что сломалось.

```bash
python3 python/check_inversion.py images/lemme_chex.raw images/lemme_chex_inv.raw
```

Для `.raw` дефолт 640×480×3, можно переопределить `--width`/`--height`/`--channels`. PNG/JPG читаются через Pillow, если он установлен. Есть `--dump-diff PATH` — сохраняет карту несовпадений отдельной картинкой.

## Тестбенч

`tb/tb_top.sv` читает входной `.raw`, гоняет через DUT и пишет выходной `.raw`. `s_tvalid` и `m_tready` рандомятся независимо (сиды `seed_src`/`seed_sink` в начале файла), `s_tdata` меняется только по handshake — модель источника без буфера, как и задумано. В конце — сравнение с эталоном `img_in[y][W-1-x]`, проверка `out_cnt` и `m_tlast`.

## Проверка результата

```bash
make run
python3 python/check_inversion.py images/lemme_chex.raw images/lemme_chex_inv.raw
python3 python/raw2img.py images/lemme_chex_inv.raw
```

Первый скрипт даёт PASS/FAIL с координатами, второй — png для визуального контроля.
