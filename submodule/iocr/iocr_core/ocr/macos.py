from iocr_core.errors import OcrUnavailableError
from iocr_core.platform import is_macos


class MacOcrBackend:
    name = "native"

    def ocr(self, png_bytes: bytes) -> str:
        if not is_macos():
            raise OcrUnavailableError("macOS Vision OCR is only available on macOS.")

        import Quartz
        import Vision

        ns_data = Quartz.NSData.dataWithBytes_length_(png_bytes, len(png_bytes))
        image_source = Quartz.CGImageSourceCreateWithData(ns_data, None)
        if image_source is None:
            raise RuntimeError("Failed to create image source")
        cg_image = Quartz.CGImageSourceCreateImageAtIndex(image_source, 0, None)
        if cg_image is None:
            raise RuntimeError("Failed to create CGImage")

        request = Vision.VNRecognizeTextRequest.alloc().init()
        request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
        request.setRecognitionLanguages_(["zh-Hans", "zh-Hant", "en"])
        request.setUsesLanguageCorrection_(True)

        handler = Vision.VNImageRequestHandler.alloc().initWithCGImage_options_(cg_image, None)
        success = handler.performRequests_error_([request], None)
        if not success[0]:
            raise RuntimeError(f"OCR failed: {success[1]}")

        results = request.results()
        if not results:
            return ""

        lines = []
        for observation in results:
            candidate = observation.topCandidates_(1)
            if candidate:
                lines.append(candidate[0].string())
        return "\n".join(lines)
