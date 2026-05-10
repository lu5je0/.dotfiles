from typing import Protocol

from iocr_core.errors import IocrError


class OcrBackend(Protocol):
    name: str

    def ocr(self, png_bytes: bytes) -> str:
        ...


class AutoOcrBackend:
    name = "auto"

    def __init__(self, backends: list[OcrBackend]):
        self.backends = backends

    def ocr(self, png_bytes: bytes) -> str:
        errors = []
        for backend in self.backends:
            try:
                text = backend.ocr(png_bytes).strip()
            except Exception as exc:
                errors.append(f"{backend.name}: {exc}")
                continue
            if text:
                return text

        if errors:
            raise IocrError("All OCR engines failed: " + "; ".join(errors))
        return ""
