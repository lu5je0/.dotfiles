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
- **OCR 引擎**: 默认 native 为系统内置 OCR，macOS 使用 Vision API，WSL 使用 Windows.Media.Ocr API（通过 PowerShell 调用 WinRT）
- **语言**: `zh-Hans-CN`、`en-US`（由 Windows 系统语言包决定）
- **系统依赖**: 无额外安装，依赖 Windows 自带 OCR 引擎

### wxocr
- **后端**: HTTP 服务，POST `{"image": "<base64 PNG>"}`，期望响应 `{"errcode": 0, "ocr_response": [{"text": ...}, ...]}`
- **默认 URL**: `http://192.168.1.10:17653/ocr`，可用 `IOCR_WXOCR_URL` 环境变量或 `--wxocr-url` 覆盖
- **auto 优先级**: 非 macOS 环境下 auto 先尝试 wxocr，失败再回落到 native（Windows OCR）

## 依赖安装

### macOS
```bash
uv sync --extra macos
```

### WSL
```bash
uv sync
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
- `--engine auto|native|wxocr`
- `--stdout` 只输出 OCR 文本，不打开 nvim
- `--wxocr-url` 指定 wxocr 服务地址（默认 `http://192.168.1.10:17653/ocr`，也可用 `IOCR_WXOCR_URL` 环境变量）

## 补全
zsh 补全文件位于 `../../zsh/completions/_oo`，修改 CLI 参数（增删选项、修改 engine 列表等）时**必须**同步更新该补全文件。
