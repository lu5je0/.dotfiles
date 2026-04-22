q-xsub

使用 `ffmpeg`/`ffprobe` 从 MKV 提取内置字幕，并按仓库内置模板生成目标样式的 `.ass` 文件。

依赖

- Python 包通过 `uv` 管理：`uv sync`
- 系统命令需要可用：`ffmpeg`、`ffprobe`

命令

- `uv run q-xsub list-templates`
- `uv run q-xsub list-streams input.mkv`
- `uv run q-xsub extract input.mkv`
- `uv run q-xsub extract a.mkv b.mkv`
- `uv run q-xsub convert sub.srt`

默认行为

- `extract` 默认优先自动寻找简体中文字幕流；若找不到，再回退到其他中文字幕流。
- 如果同时找到英文字幕流，会合并成双语 ASS，中文在上，英文在下，并对英文行套用 `Eng` 样式。
- 如果只找到中文字幕流，则只输出中文。
- `convert` 和 `extract --stream` 默认不会拆中英行；加 `--split-zh-and-en-lines` 后，会把单轨中英混合字幕拆成中文在上、英文在下。
- 英文默认套用 `Eng` 样式；可用 `--no-english-standalone-font` 关闭，这个开关在 `convert`、`extract --stream` 和 `extract` 自动双流合并时都生效。
- 如果自动模式找不到简中流，可先运行 `uv run q-xsub list-streams input.mkv`，再用 `--stream` 手动指定。

示例

```bash
uv sync
uv run q-xsub list-templates
uv run q-xsub list-streams movie.mkv
uv run q-xsub extract movie.mkv -t 2
uv run q-xsub extract ep1.mkv ep2.mkv
uv run q-xsub extract movie.mkv --stream 0
uv run q-xsub extract movie.mkv --stream 0 -s
uv run q-xsub extract movie.mkv --no-english-standalone-font
uv run q-xsub convert input.srt -t 3
uv run q-xsub convert input.srt -t 3 -s
uv run q-xsub convert input.srt -t 3 --no-english-standalone-font
```

兼容 pyass 的功能

- 支持内置模板名，如 `1`、`2`、`3`
- 支持直接传入自定义模板路径
- `convert` 子命令支持 `.srt` 和 `.ass`
- `--split-zh-and-en-lines` 控制单轨中英混合字幕是否拆成上下两行
- `--no-english-standalone-font` 关闭英文的 `Eng` 样式；默认开启，单轨和双流都可用
