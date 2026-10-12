import io
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass

from .errors import IocrError
from .platform import find_powershell, is_macos, is_wsl


@dataclass(frozen=True)
class ImageInput:
    png_bytes: bytes
    source: str


class ImageReader:
    def __init__(self):
        from PIL import Image

        self.Image = Image

    def read(self, file_path: str | None) -> ImageInput:
        if file_path:
            if not os.path.isfile(file_path):
                raise IocrError(f"File not found: {file_path}")
            with open(file_path, "rb") as f:
                raw = f.read()
            png_bytes = self.image_from_bytes(raw)
            if png_bytes is None:
                raise IocrError(f"Failed to decode image: {file_path}")
            return ImageInput(png_bytes=png_bytes, source=file_path)

        if not sys.stdin.isatty():
            raw = sys.stdin.buffer.read()
            png_bytes = self.image_from_bytes(raw)
            if png_bytes is None:
                raise IocrError("Failed to decode image from stdin.")
            return ImageInput(png_bytes=png_bytes, source="stdin")

        png_bytes = self.get_clipboard_image()
        if png_bytes is None:
            raise IocrError("No image found in clipboard.")
        return ImageInput(png_bytes=png_bytes, source="clipboard")

    def image_from_bytes(self, data: bytes) -> bytes | None:
        return self._to_png_bytes(data)

    def get_clipboard_image(self) -> bytes | None:
        if is_macos():
            return self._get_macos_clipboard_image()
        if is_wsl():
            return self._get_wsl_clipboard_image()
        return None

    def _to_png_bytes(self, data: bytes) -> bytes | None:
        try:
            img = self.Image.open(io.BytesIO(data))
            img.load()
            out = io.BytesIO()
            img.save(out, format="PNG")
            return out.getvalue()
        except Exception:
            return None

    def _get_macos_clipboard_image(self) -> bytes | None:
        import Quartz

        pasteboard = Quartz.NSPasteboard.generalPasteboard()
        types = pasteboard.types()
        if Quartz.NSPasteboardTypeTIFF not in types and Quartz.NSPasteboardTypePNG not in types:
            return None

        img_type = (
            Quartz.NSPasteboardTypePNG
            if Quartz.NSPasteboardTypePNG in types
            else Quartz.NSPasteboardTypeTIFF
        )
        data = pasteboard.dataForType_(img_type)
        if data is None:
            return None

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

    def _get_wsl_clipboard_image(self) -> bytes | None:
        tmp_path = os.path.join(tempfile.gettempdir(), "iocr_clipboard.png")
        try:
            win_tmp = subprocess.run(
                ["wslpath", "-w", tmp_path],
                capture_output=True,
                text=True,
            ).stdout.strip()
        except Exception:
            win_tmp = tmp_path

        ps_cmd = (
            "Add-Type -Assembly System.Windows.Forms; "
            "$img = [System.Windows.Forms.Clipboard]::GetImage(); "
            f"if ($img) {{ $img.Save('{win_tmp}'); Write-Host 'OK' }} "
            "else { Write-Host 'NO_IMAGE' }"
        )

        ps_exe = find_powershell()
        if not ps_exe:
            return None

        try:
            result = subprocess.run(
                [ps_exe, "-Command", ps_cmd],
                capture_output=True,
                text=True,
            )
            if "OK" not in result.stdout:
                return None
            with open(tmp_path, "rb") as f:
                data = f.read()
            return self._to_png_bytes(data)
        except Exception:
            return None
        finally:
            try:
                os.remove(tmp_path)
            except Exception:
                pass
