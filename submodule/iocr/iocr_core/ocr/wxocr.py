import base64
import json
import os
import urllib.error
import urllib.request
from typing import Any

from iocr_core.errors import IocrError, OcrUnavailableError

DEFAULT_WXOCR_URL = "http://192.168.1.3:17653/ocr"
WXOCR_URL_ENV = "IOCR_WXOCR_URL"


class WxOcrBackend:
    name = "wxocr"

    def __init__(self, url: str | None = None, timeout: float = 30.0):
        self.url = url or os.environ.get(WXOCR_URL_ENV) or DEFAULT_WXOCR_URL
        self.timeout = timeout

    def ocr(self, png_bytes: bytes) -> str:
        payload = json.dumps({"image": base64.b64encode(png_bytes).decode("ascii")}).encode("utf-8")
        request = urllib.request.Request(
            self.url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                body = response.read()
        except urllib.error.URLError as exc:
            raise OcrUnavailableError(
                f"wxocr request to {self.url} failed: {exc}"
            ) from exc

        try:
            data = json.loads(body.decode("utf-8", errors="replace"))
        except json.JSONDecodeError as exc:
            raise IocrError(f"wxocr returned non-JSON response: {exc}") from exc

        return extract_wxocr_text(data)


def extract_wxocr_text(data: Any) -> str:
    if isinstance(data, dict):
        errcode = data.get("errcode")
        if errcode not in (None, 0):
            message = data.get("errmsg") or data.get("message") or f"errcode={errcode}"
            raise IocrError(f"wxocr error: {message}")
        items = data.get("ocr_response")
        if isinstance(items, list):
            return "\n".join(
                str(item.get("text", "")).rstrip()
                for item in items
                if isinstance(item, dict) and item.get("text")
            )
    return ""
