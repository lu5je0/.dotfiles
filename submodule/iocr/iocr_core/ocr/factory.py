from iocr_core.errors import OcrUnavailableError
from iocr_core.platform import is_macos, is_wsl

from .base import AutoOcrBackend, OcrBackend
from .macos import MacOcrBackend
from .windows import WindowsOcrBackend
from .wxocr import WxOcrBackend

ENGINE_CHOICES = ("auto", "native", "wxocr")


def create_ocr_backend(
    engine: str,
    *,
    wxocr_url: str | None = None,
) -> OcrBackend:
    if engine == "auto":
        return AutoOcrBackend(_auto_backends(wxocr_url=wxocr_url))
    if engine == "native":
        backends = _native_backends()
        if not backends:
            raise OcrUnavailableError("No native OCR backend is available on this platform.")
        return backends[0]
    if engine == "wxocr":
        return WxOcrBackend(url=wxocr_url)
    raise OcrUnavailableError(f"Unknown OCR engine: {engine}")


def _auto_backends(
    *,
    wxocr_url: str | None,
) -> list[OcrBackend]:
    if is_macos():
        return [MacOcrBackend()]
    return [
        WxOcrBackend(url=wxocr_url),
        *_native_backends(),
    ]


def _native_backends() -> list[OcrBackend]:
    if is_macos():
        return [MacOcrBackend()]
    if is_wsl():
        return [WindowsOcrBackend()]
    return []
