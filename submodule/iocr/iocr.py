#!/usr/bin/env python3

import os
import subprocess
import sys

from _platform import is_wsl


def main():
    import argparse

    parser = argparse.ArgumentParser(
        prog="iocr",
        description="OCR an image and open the result in nvim.",
    )
    parser.add_argument(
        "file",
        nargs="?",
        help="image file path (reads from clipboard if omitted)",
    )
    args = parser.parse_args()

    if sys.platform == "darwin":
        from backend_mac import MacImageBackend, MacOcrBackend

        image_backend = MacImageBackend()
        ocr_backend = MacOcrBackend()
    else:
        from backend_wsl import WindowsOcrBackend, WslImageBackend

        image_backend = WslImageBackend()
        ocr_backend = WindowsOcrBackend()

    if args.file:
        if not os.path.isfile(args.file):
            print(f"File not found: {args.file}", file=sys.stderr)
            sys.exit(1)
        with open(args.file, "rb") as f:
            raw = f.read()
        png_bytes = image_backend.image_from_bytes(raw)
        if png_bytes is None:
            print(f"Failed to decode image: {args.file}", file=sys.stderr)
            sys.exit(1)
    elif not sys.stdin.isatty():
        raw = sys.stdin.buffer.read()
        png_bytes = image_backend.image_from_bytes(raw)
        if png_bytes is None:
            print("Failed to decode image from stdin.", file=sys.stderr)
            sys.exit(1)
    else:
        png_bytes = image_backend.get_clipboard_image()
        if png_bytes is None:
            print("No image found in clipboard.", file=sys.stderr)
            sys.exit(1)

    text = ocr_backend.ocr(png_bytes)
    if not text:
        print("OCR returned no text.", file=sys.stderr)
        sys.exit(1)

    tmp_dir = "/tmp/iocr"
    os.makedirs(tmp_dir, exist_ok=True)
    img_path = os.path.join(tmp_dir, "source.png")
    md_path = os.path.join(tmp_dir, "ocr.md")

    with open(img_path, "wb") as f:
        f.write(png_bytes)

    content = f"![ocr]({img_path})\n\n---\n\n{text}\n"
    with open(md_path, "w") as f:
        f.write(content)

    subprocess.run(["nvim", md_path])


if __name__ == "__main__":
    main()
