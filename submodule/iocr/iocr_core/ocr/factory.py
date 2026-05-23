from iocr_core.errors import OcrUnavailableError
from iocr_core.platform import is_macos, is_wsl

from .base import AutoOcrBackend, OcrBackend
from .macos import MacOcrBackend
from .paddle import PaddleOcrBackend
from .windows import WindowsOcrBackend
from .wxocr import WxOcrBackend

ENGINE_CHOICES = ("auto", "native", "paddle", "wxocr")


def create_ocr_backend(
    engine: str,
    *,
    paddle_device: str | None = None,
    wxocr_url: str | None = None,
) -> OcrBackend:
    if engine == "auto":
        return AutoOcrBackend(_auto_backends(paddle_device=paddle_device, wxocr_url=wxocr_url))
    if engine == "native":
        backends = _native_backends()
        if not backends:
            raise OcrUnavailableError("No native OCR backend is available on this platform.")
        return backends[0]
    if engine == "paddle":
        return PaddleOcrBackend(device=paddle_device)
    if engine == "wxocr":
        return WxOcrBackend(url=wxocr_url)
    raise OcrUnavailableError(f"Unknown OCR engine: {engine}")


def _auto_backends(
    *,
    paddle_device: str | None,
    wxocr_url: str | None,
) -> list[OcrBackend]:
    if is_macos():
        return [MacOcrBackend(), PaddleOcrBackend(device=paddle_device)]
    return [
        WxOcrBackend(url=wxocr_url),
        *_native_backends(),
        PaddleOcrBackend(device=paddle_device),
    ]


def _native_backends() -> list[OcrBackend]:
    if is_macos():
        return [MacOcrBackend()]
    if is_wsl():
        return [WindowsOcrBackend()]
    return []
