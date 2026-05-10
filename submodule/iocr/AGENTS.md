# iocr

## 概述
跨平台图片 OCR 工具，支持 macOS 和 WSL。主命令名为 `oo`，保留 `iocr` 入口兼容。读取图片（剪贴板/文件/stdin）后识别文字，结果可在 nvim 中展示（含原图预览），也可直接输出到 stdout。

## 项目结构
- `iocr.py` — 兼容 wrapper，转发到 `iocr_core.cli`
- `iocr_core/cli.py` — CLI 参数与主流程
- `iocr_core/image.py` — 输入源读取与图片转 PNG
- `iocr_core/output.py` — stdout/nvim 输出
- `iocr_core/ocr/` — 可扩展 OCR 引擎后端
- `pyproject.toml` — uv 管理，entry point: `oo` 与 `iocr`
- `.python-version` — Python 版本锁定

## 平台支持

### macOS
- **剪贴板/图片处理**: Quartz (`pyobjc-framework-quartz`)
- **OCR 引擎**: Vision API (`pyobjc-framework-vision`)
- **语言**: 简体中文、繁体中文、英文

### WSL
- **剪贴板**: 通过 `powershell.exe` 调用 Windows `[System.Windows.Forms.Clipboard]` 读取图片
- **图片处理**: Pillow
- **OCR 引擎**: 默认 native 为系统内置 OCR，macOS 使用 Vision API，WSL 使用 Windows.Media.Ocr API（通过 PowerShell 调用 WinRT）；可选 PaddleOCR PP-OCRv5 server
- **语言**: `zh-Hans-CN`、`en-US`（由 Windows 系统语言包决定）
- **系统依赖**: 无额外安装，依赖 Windows 自带 OCR 引擎
- **PaddleOCR**: 使用最新版 PaddleOCR，并显式选择 `PP-OCRv5_server_det` 与 `PP-OCRv5_server_rec`；依赖较重，模型/缓存目录为 `${XDG_CACHE_HOME:-~/.cache}/paddlex`，CPU 下默认关闭 Paddle 的 MKLDNN 路径以避开当前 oneDNN/PIR 回归

## 依赖安装

### macOS
```bash
uv sync --extra macos
```

### WSL
```bash
uv sync
```

### PaddleOCR
```bash
uv sync --extra paddle
```

## 输入源优先级
1. 命令行参数指定文件路径
2. stdin 管道输入
3. 系统剪贴板

## 开发
```bash
uv run oo
```

常用参数：
- `--engine auto|native|paddle`
- `--stdout` 只输出 OCR 文本，不打开 nvim
- `--paddle-device` 指定 PaddleOCR 设备，例如 `cpu` 或 `gpu:0`

## 补全
zsh 补全文件位于 `../../zsh/completions/_oo`，修改 CLI 参数时需同步更新。
