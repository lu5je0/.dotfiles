# iocr

## 概述
跨平台图片 OCR 工具，支持 macOS 和 WSL。读取图片（剪贴板/文件/stdin）后识别文字，结果在 nvim 中展示（含原图预览）。

## 项目结构
- `iocr.py` — 主程序入口
- `pyproject.toml` — uv 管理，entry point: `iocr`
- `.python-version` — Python 版本锁定

## 平台支持

### macOS
- **剪贴板/图片处理**: Quartz (`pyobjc-framework-quartz`)
- **OCR 引擎**: Vision API (`pyobjc-framework-vision`)
- **语言**: 简体中文、繁体中文、英文

### WSL
- **剪贴板**: 通过 `powershell.exe` 调用 Windows `[System.Windows.Forms.Clipboard]` 读取图片
- **图片处理**: Pillow
- **OCR 引擎**: Windows.Media.Ocr API（通过 PowerShell 调用 WinRT）
- **语言**: `zh-Hans-CN`、`en-US`（由 Windows 系统语言包决定）
- **系统依赖**: 无额外安装，依赖 Windows 自带 OCR 引擎

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
uv run iocr
```

## 补全
zsh 补全文件位于 `../../zsh/completions/_iocr`，修改 CLI 参数时需同步更新。
