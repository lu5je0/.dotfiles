from iocr_core.errors import OcrUnavailableError
from iocr_core.platform import is_macos, is_wsl

from .base import AutoOcrBackend, OcrBackend
from .macos import MacOcrBackend
from .paddle import PaddleOcrBackend
from .windows import WindowsOcrBackend

ENGINE_CHOICES = ("auto", "native", "paddle")


def create_ocr_backend(
    engine: str,
    *,
    paddle_device: str | None = None,
) -> OcrBackend:
    if engine == "auto":
        return AutoOcrBackend(
            [
                *_native_backends(),
                PaddleOcrBackend(device=paddle_device),
            ]
        )
    if engine == "native":
        backends = _native_backends()
        if not backends:
            raise OcrUnavailableError("No native OCR backend is available on this platform.")
        return backends[0]
    if engine == "paddle":
        return PaddleOcrBackend(device=paddle_device)
    raise OcrUnavailableError(f"Unknown OCR engine: {engine}")


def _native_backends() -> list[OcrBackend]:
    if is_macos():
        return [MacOcrBackend()]
    if is_wsl():
        return [WindowsOcrBackend()]
    return []
