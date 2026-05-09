class MacImageBackend:
    def get_clipboard_image(self) -> bytes | None:
        import Quartz

        pasteboard = Quartz.NSPasteboard.generalPasteboard()
        types = pasteboard.types()
        if Quartz.NSPasteboardTypeTIFF not in types and Quartz.NSPasteboardTypePNG not in types:
            return None

        img_type = Quartz.NSPasteboardTypePNG if Quartz.NSPasteboardTypePNG in types else Quartz.NSPasteboardTypeTIFF
        data = pasteboard.dataForType_(img_type)
        if data is None:
            return None

        return self._to_png_bytes(data)

    def image_from_bytes(self, data: bytes) -> bytes | None:
        import Quartz

        ns_data = Quartz.NSData.dataWithBytes_length_(data, len(data))
        return self._to_png_bytes(ns_data)

    def _to_png_bytes(self, data) -> bytes | None:
        import Quartz

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
        return bytes(mutable_data)


class MacOcrBackend:
    def ocr(self, png_bytes: bytes) -> str:
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
