import io
import os
import subprocess
import tempfile

from _platform import find_powershell, is_wsl, to_win_path


class WslImageBackend:
    def __init__(self):
        from PIL import Image

        self.Image = Image

    def get_clipboard_image(self) -> bytes | None:
        if not is_wsl():
            return None

        tmp_path = os.path.join(tempfile.gettempdir(), "iocr_clipboard.png")
        try:
            win_tmp = subprocess.run(
                ["wslpath", "-w", tmp_path], capture_output=True, text=True
            ).stdout.strip()
        except Exception:
            win_tmp = tmp_path

        ps_cmd = (
            f'Add-Type -Assembly System.Windows.Forms; '
            f'$img = [System.Windows.Forms.Clipboard]::GetImage(); '
            f"if ($img) {{ $img.Save('{win_tmp}'); Write-Host 'OK' }} "
            f"else {{ Write-Host 'NO_IMAGE' }}"
        )

        ps_exe = find_powershell()
        if not ps_exe:
            return None

        try:
            result = subprocess.run([ps_exe, "-Command", ps_cmd], capture_output=True, text=True)
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

    def image_from_bytes(self, data: bytes) -> bytes | None:
        return self._to_png_bytes(data)

    def _to_png_bytes(self, data: bytes) -> bytes | None:
        try:
            img = self.Image.open(io.BytesIO(data))
            img.load()
            out = io.BytesIO()
            img.save(out, format="PNG")
            return out.getvalue()
        except Exception:
            return None


class WindowsOcrBackend:
    def ocr(self, png_bytes: bytes) -> str:
        tmp_path = os.path.join(tempfile.gettempdir(), "iocr_ocr_input.png")
        with open(tmp_path, "wb") as f:
            f.write(png_bytes)

        win_path = to_win_path(tmp_path)
        ps_script = r'''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Runtime.WindowsRuntime

[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder,Windows.Foundation,ContentType=WindowsRuntime] | Out-Null
[Windows.Storage.Streams.RandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime] | Out-Null

$Asyn = [System.WindowsRuntimeSystemExtensions].GetMethods() | ? {
    $_.Name -eq 'AsTask' -and
    $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
}

function Await($WinRtTask, $ResultType) {
    $asTaskGeneric = $Asyn | ? { -not $_.IsGenericMethod }
    if (-not $asTaskGeneric) {
        $asTaskGeneric = $Asyn | ? { $_.IsGenericMethod } | Select -First 1
        $asTaskGeneric = $asTaskGeneric.MakeGenericMethod($ResultType)
    }
    $netTask = $asTaskGeneric.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}

$imgPath = '__IMG_PATH__'
$stream = [System.IO.File]::OpenRead($imgPath)
$randomStream = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($stream)

$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($randomStream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])

$langs = @('zh-Hans-CN', 'en-US')
$allText = @()
foreach ($lang in $langs) {
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
    if ($engine) {
        $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
        if ($result.Lines.Count -gt 0) {
            $lines = @()
            foreach ($line in $result.Lines) {
                $words = @($line.Words)
                $lineText = ''
                for ($i = 0; $i -lt $words.Count; $i++) {
                    $w = $words[$i].Text
                    if ($i -gt 0) {
                        $prevChar = $lineText[-1]
                        $currChar = $w[0]
                        $prevIsAscii = [int]$prevChar -lt 128
                        $currIsAscii = [int]$currChar -lt 128
                        if ($prevIsAscii -or $currIsAscii) {
                            $lineText += ' '
                        }
                    }
                    $lineText += $w
                }
                $lines += $lineText
            }
            $allText += ($lines -join "`n")
        }
    }
}

$stream.Close()

if ($allText.Count -gt 0) {
    Write-Host ($allText[0])
} else {
    Write-Host ''
}
'''.replace('__IMG_PATH__', win_path)
        ps_exe = find_powershell()
        if not ps_exe:
            raise RuntimeError("PowerShell not found")

        try:
            result = subprocess.run(
                [ps_exe, "-Command", ps_script],
                capture_output=True, timeout=30,
            )
            if result.returncode != 0:
                stderr = result.stderr.decode("utf-8", errors="replace")
                raise RuntimeError(f"Windows OCR failed: {stderr.strip()}")
            return result.stdout.decode("utf-8", errors="replace").strip()
        finally:
            try:
                os.remove(tmp_path)
            except Exception:
                pass
