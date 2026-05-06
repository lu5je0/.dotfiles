# iocr

## 概述
macOS 剪切板/文件图片 OCR 工具，使用 macOS Vision API 识别文字，结果在 nvim 中展示（含原图预览）。

## 项目结构
- `iocr.py` — 主程序入口
- `pyproject.toml` — uv 管理，entry point: `iocr`
- `.python-version` — Python 版本锁定

## 依赖
- `pyobjc-framework-vision` — macOS Vision API
- `pyobjc-framework-quartz` — 剪切板和图片处理

## 输入源优先级
1. 命令行参数指定文件路径
2. stdin 管道输入
3. 系统剪切板

## 开发
```bash
uv sync
uv run iocr
```

## 补全
zsh 补全文件位于 `../../zsh/completions/_iocr`，修改 CLI 参数时需同步更新。
