import os
import subprocess
import tempfile

from iocr_core.errors import OcrUnavailableError
from iocr_core.platform import find_powershell, is_wsl, to_win_path


class WindowsOcrBackend:
    name = "native"

    def ocr(self, png_bytes: bytes) -> str:
        if not is_wsl():
            raise OcrUnavailableError("Windows OCR is only available under WSL.")

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
            raise OcrUnavailableError("PowerShell not found")

        try:
            result = subprocess.run(
                [ps_exe, "-Command", ps_script],
                capture_output=True,
                timeout=30,
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
