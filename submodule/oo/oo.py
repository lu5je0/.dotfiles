#!/usr/bin/env python3

import subprocess
import sys
import tempfile

import Quartz
import Vision


def get_clipboard_image() -> Quartz.CGImage | None:
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

    return Quartz.CGImageSourceCreateImageAtIndex(image_source, 0, None)


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
    cg_image = get_clipboard_image()
    if cg_image is None:
        print("No image found in clipboard.", file=sys.stderr)
        sys.exit(1)

    text = ocr(cg_image)
    if not text:
        print("OCR returned no text.", file=sys.stderr)
        sys.exit(1)

    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
        f.write(text)
        tmp_path = f.name

    subprocess.run(["nvim", tmp_path])


if __name__ == "__main__":
    main()
