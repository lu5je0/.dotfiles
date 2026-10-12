class IocrError(RuntimeError):
    """Base error for user-facing iocr failures."""


class OcrUnavailableError(IocrError):
    """Raised when an OCR engine cannot run in the current environment."""
