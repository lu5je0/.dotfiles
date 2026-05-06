#!/usr/bin/env python3

import argparse
import os
import subprocess
import sys

import Quartz
import Vision


def get_clipboard_image() -> tuple[Quartz.CGImage, bytes] | None:
    pasteboard = Quartz.NSPasteboard.generalPasteboard()
    types = pasteboard.types()
    if Quartz.NSPasteboardTypeTIFF not in types and Quartz.NSPasteboardTypePNG not in types:
        return None

    img_type = Quartz.NSPasteboardTypePNG if Quartz.NSPasteboardTypePNG in types else Quartz.NSPasteboardTypeTIFF
    data = pasteboard.dataForType_(img_type)
    if data is None:
        return None

    image_source = Quartz.CGImageSourceCreateWithData(data, None)
    if image_source is None:
        return None

    cg_image = Quartz.CGImageSourceCreateImageAtIndex(image_source, 0, None)
    if cg_image is None:
        return None

    mutable_data = Quartz.CFDataCreateMutable(None, 0)
    dest = Quartz.CGImageDestinationCreateWithData(mutable_data, "public.png", 1, None)
    Quartz.CGImageDestinationAddImage(dest, cg_image, None)
    Quartz.CGImageDestinationFinalize(dest)
    png_bytes = bytes(mutable_data)

    return cg_image, png_bytes


def image_from_bytes(data: bytes) -> tuple[Quartz.CGImage, bytes] | None:
    ns_data = Quartz.NSData.dataWithBytes_length_(data, len(data))
    image_source = Quartz.CGImageSourceCreateWithData(ns_data, None)
    if image_source is None:
        return None
    cg_image = Quartz.CGImageSourceCreateImageAtIndex(image_source, 0, None)
    if cg_image is None:
        return None

    mutable_data = Quartz.CFDataCreateMutable(None, 0)
    dest = Quartz.CGImageDestinationCreateWithData(mutable_data, "public.png", 1, None)
    Quartz.CGImageDestinationAddImage(dest, cg_image, None)
    Quartz.CGImageDestinationFinalize(dest)
    png_bytes = bytes(mutable_data)

    return cg_image, png_bytes


def ocr(cg_image: Quartz.CGImage) -> str:
    request = Vision.VNRecognizeTextRequest.alloc().init()
    request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
    request.setRecognitionLanguages_(["zh-Hans", "zh-Hant", "en"])
    request.setUsesLanguageCorrection_(True)

    handler = Vision.VNImageRequestHandler.alloc().initWithCGImage_options_(cg_image, None)
    success = handler.performRequests_error_([request], None)
    if not success[0]:
        print(f"OCR failed: {success[1]}", file=sys.stderr)
        sys.exit(1)

    results = request.results()
    if not results:
        return ""

    lines = []
    for observation in results:
        candidate = observation.topCandidates_(1)
        if candidate:
            lines.append(candidate[0].string())
    return "\n".join(lines)


def main():
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

    if args.file:
        if not os.path.isfile(args.file):
            print(f"File not found: {args.file}", file=sys.stderr)
            sys.exit(1)
        with open(args.file, "rb") as f:
            raw = f.read()
        result = image_from_bytes(raw)
        if result is None:
            print(f"Failed to decode image: {args.file}", file=sys.stderr)
            sys.exit(1)
    elif not sys.stdin.isatty():
        raw = sys.stdin.buffer.read()
        result = image_from_bytes(raw)
        if result is None:
            print("Failed to decode image from stdin.", file=sys.stderr)
            sys.exit(1)
    else:
        result = get_clipboard_image()
        if result is None:
            print("No image found in clipboard.", file=sys.stderr)
            sys.exit(1)

    cg_image, png_bytes = result

    tmp_dir = "/tmp/iocr"
    os.makedirs(tmp_dir, exist_ok=True)
    img_path = os.path.join(tmp_dir, "source.png")
    md_path = os.path.join(tmp_dir, "ocr.md")

    with open(img_path, "wb") as f:
        f.write(png_bytes)

    text = ocr(cg_image)
    if not text:
        print("OCR returned no text.", file=sys.stderr)
        sys.exit(1)

    content = f"![ocr]({img_path})\n\n---\n\n{text}\n"
    with open(md_path, "w") as f:
        f.write(content)

    subprocess.run(["nvim", md_path])


if __name__ == "__main__":
    main()
