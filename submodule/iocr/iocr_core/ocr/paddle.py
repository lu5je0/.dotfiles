import contextlib
import io
import json
import os
import tempfile
from typing import Any

from iocr_core.errors import OcrUnavailableError

PADDLE_DET_MODEL = "PP-OCRv5_server_det"
PADDLE_REC_MODEL = "PP-OCRv5_server_rec"


class PaddleOcrBackend:
    name = "paddle"

    def __init__(self, device: str | None = None):
        self.device = device

    def ocr(self, png_bytes: bytes) -> str:
        tmp_path = os.path.join(tempfile.gettempdir(), "iocr_paddle_input.png")
        with open(tmp_path, "wb") as f:
            f.write(png_bytes)

        try:
            return run_paddle_ocr(tmp_path, device=self.device)
        finally:
            try:
                os.remove(tmp_path)
            except Exception:
                pass


def run_paddle_ocr(image_path: str, device: str | None = None) -> str:
    _prepare_paddle_runtime(device)

    logs = io.StringIO()
    try:
        with contextlib.redirect_stdout(logs), contextlib.redirect_stderr(logs):
            from paddleocr import PaddleOCR
    except Exception as exc:
        raise OcrUnavailableError(
            "PaddleOCR is not available. Install it with "
            "`uv sync --extra paddle` or `python -m pip install paddlepaddle paddleocr`."
        ) from exc

    kwargs = {
        "text_detection_model_name": PADDLE_DET_MODEL,
        "text_recognition_model_name": PADDLE_REC_MODEL,
        "use_doc_orientation_classify": False,
        "use_doc_unwarping": False,
        "use_textline_orientation": False,
    }
    if device:
        kwargs["device"] = device

    try:
        with contextlib.redirect_stdout(logs), contextlib.redirect_stderr(logs):
            ocr = PaddleOCR(**kwargs)
            result = ocr.predict(image_path)
    except Exception as exc:
        message = str(exc)
        captured = logs.getvalue().strip()
        if captured:
            message = f"{message}\n\nPaddleOCR logs:\n{captured}"
        raise RuntimeError(message) from exc
    return extract_paddle_text(result)


def _prepare_paddle_runtime(device: str | None) -> None:
    xdg_cache_home = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
    os.environ.setdefault("PADDLE_PDX_CACHE_HOME", os.path.join(xdg_cache_home, "paddlex"))

    if device is None or device == "cpu":
        # PaddlePaddle 3.3.x can fail on CPU oneDNN/PIR conversion for PP-OCRv5.
        os.environ.setdefault("PADDLE_PDX_ENABLE_MKLDNN_BYDEFAULT", "0")


def extract_paddle_text(result: Any) -> str:
    lines: list[str] = []

    def visit(obj: Any) -> None:
        data = _as_json_data(obj)
        if data is not obj:
            visit(data)
            return

        if isinstance(obj, dict):
            rec_texts = obj.get("rec_texts")
            if isinstance(rec_texts, list):
                lines.extend(str(text) for text in rec_texts if text)
                return
            for value in obj.values():
                visit(value)
            return

        if isinstance(obj, (list, tuple)):
            if _looks_like_legacy_line(obj):
                lines.append(str(obj[1][0]))
                return
            if len(obj) >= 3 and isinstance(obj[1], str):
                lines.append(obj[1])
                return
            for value in obj:
                visit(value)

    visit(result)
    return "\n".join(lines)


def _as_json_data(obj: Any) -> Any:
    if isinstance(obj, (dict, list, tuple, str, int, float, type(None))):
        return obj

    data = getattr(obj, "json", None)
    if callable(data):
        data = data()
    if data is not None:
        if isinstance(data, str):
            try:
                return json.loads(data)
            except json.JSONDecodeError:
                return data
        return data
    return obj


def _looks_like_legacy_line(obj: Any) -> bool:
    return (
        isinstance(obj, (list, tuple))
        and len(obj) >= 2
        and isinstance(obj[1], (list, tuple))
        and len(obj[1]) >= 1
        and isinstance(obj[1][0], str)
    )
