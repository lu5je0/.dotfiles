# oo

Cross-platform image OCR for macOS and WSL. It reads an image from a file,
stdin, or the clipboard, then either opens a markdown preview in nvim or prints
the recognized text to stdout.

## Usage

```bash
oo [image]
oo --stdout [image]
oo --engine paddle --stdout [image]
```

Input priority:

1. positional image file
2. stdin
3. clipboard

OCR engines:

- `auto`: native OCR first, then PaddleOCR
- `native`: system OCR: macOS Vision on macOS, Windows.Media.Ocr under WSL
- `paddle`: PaddleOCR PP-OCRv5 server (`PP-OCRv5_server_det` +
  `PP-OCRv5_server_rec`)

PaddleOCR is optional and heavy:

```bash
uv sync --extra paddle
```

PaddleX model/cache files are stored under `${XDG_CACHE_HOME:-~/.cache}/paddlex`.
