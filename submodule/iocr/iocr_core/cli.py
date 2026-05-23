import argparse
import os
import sys

from .errors import IocrError
from .image import ImageReader
from .ocr.factory import ENGINE_CHOICES, create_ocr_backend
from .output import open_in_editor, print_text


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="oo",
        description="OCR an image from file, stdin, or clipboard.",
    )
    parser.add_argument(
        "file",
        nargs="?",
        help="image file path (reads stdin first, then clipboard if omitted)",
    )
    parser.add_argument(
        "-e",
        "--engine",
        choices=ENGINE_CHOICES,
        default="auto",
        help=(
            "OCR engine: auto, native (macOS Vision or Windows OCR), paddle "
            "(PP-OCRv5 server), wxocr (HTTP service)"
        ),
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="print recognized text to stdout instead of opening nvim",
    )
    parser.add_argument(
        "--editor",
        default=os.environ.get("EDITOR", "nvim"),
        help="editor command used for markdown preview output (default: nvim or EDITOR)",
    )
    parser.add_argument(
        "--paddle-device",
        help="PaddleOCR device, e.g. cpu, gpu, or gpu:0",
    )
    parser.add_argument(
        "--wxocr-url",
        help="wxocr endpoint URL (overrides IOCR_WXOCR_URL env var)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        image = ImageReader().read(args.file)
        backend = create_ocr_backend(
            args.engine,
            paddle_device=args.paddle_device,
            wxocr_url=args.wxocr_url,
        )
        text = backend.ocr(image.png_bytes).strip()
        if not text:
            raise IocrError("OCR returned no text.")

        if args.stdout:
            print_text(text)
        else:
            open_in_editor(image.png_bytes, text, editor=args.editor)
        return 0
    except KeyboardInterrupt:
        return 130
    except IocrError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"oo failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
