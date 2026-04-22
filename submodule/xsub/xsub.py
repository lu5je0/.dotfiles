from __future__ import annotations

import argparse
import importlib
import json
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent
TEMPLATE_DIR = PROJECT_ROOT / "template"
TEXT_SUBTITLE_CODECS = {
    "ass",
    "mov_text",
    "srt",
    "ssa",
    "subrip",
    "text",
    "webvtt",
}


@dataclass
class SubtitleStream:
    stream_index: int
    subtitle_index: int
    codec_name: str
    language: str
    title: str


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def describe_stream(stream: SubtitleStream) -> str:
    title = f" title={stream.title}" if stream.title else ""
    return (
        f"[{stream.subtitle_index}] codec={stream.codec_name} "
        f"language={stream.language} ffmpeg-map=0:s:{stream.subtitle_index}{title}"
    )


def require_dependency(name: str):
    try:
        return importlib.import_module(name)
    except ModuleNotFoundError as exc:
        raise SystemExit(f"缺少 Python 依赖 {name}，请先运行 `uv sync`。") from exc


def run_command(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def ensure_tool_installed(name: str) -> None:
    result = run_command([name, "-version"])
    if result.returncode != 0:
        raise SystemExit(f"未找到 {name}，请先安装。")


def detect_file_encoding(file_path: Path) -> str:
    chardet = require_dependency("chardet")
    with file_path.open("rb") as handle:
        result = chardet.detect(handle.read())
    return result.get("encoding") or "utf-8"


def read_ass_template(template_path: Path) -> str:
    return template_path.read_text(encoding="utf-8-sig").strip()


def is_chinese_line(line: str) -> bool:
    return any("\u4e00" <= char <= "\u9fff" for char in line)


def normalize_language(value: str) -> str:
    return value.strip().lower().replace("_", "-")


def list_builtin_templates() -> list[str]:
    if not TEMPLATE_DIR.exists():
        return []
    return [path.stem for path in sorted(TEMPLATE_DIR.glob("*.ass"))]


def resolve_template_path(template: str) -> Path:
    candidate = Path(template).expanduser()
    if candidate.exists():
        return candidate.resolve()

    named = TEMPLATE_DIR / f"{template}.ass"
    if named.exists():
        return named.resolve()

    raise SystemExit(f"找不到模板: {template}")


def format_ass_timestamp(subrip_time) -> str:
    hours = subrip_time.hours
    minutes = subrip_time.minutes
    seconds = subrip_time.seconds
    centiseconds = subrip_time.milliseconds // 10
    return f"{hours}:{minutes:02}:{seconds:02}.{centiseconds:02}"


def normalize_multiline_text(text: str) -> str:
    return "\\N".join(part.strip() for part in text.splitlines() if part.strip())


def flatten_multiline_text(text: str) -> str:
    return " ".join(part.strip() for part in text.splitlines() if part.strip())


def style_english_lines(text: str, english_standalone_font: bool) -> str:
    styled_lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if not english_standalone_font:
            styled_lines.append(stripped)
            continue
        if is_chinese_line(stripped):
            styled_lines.append(stripped)
        else:
            styled_lines.append(r"{\rEng}" + stripped)
    return "\\N".join(styled_lines)


def convert_pyass_text(text: str, split_zh_and_en_lines: bool, english_standalone_font: bool) -> str:
    eng_font = r"{\rEng}" if english_standalone_font else ""
    if not split_zh_and_en_lines:
        return style_english_lines(text, english_standalone_font)

    merged = ""
    append_newline = False
    contain_chinese = False
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        if is_chinese_line(line):
            merged = merged + ("" if merged == "" else " ") + line
            contain_chinese = True
        else:
            if contain_chinese and not append_newline and merged:
                merged += f"\\N{eng_font}"
                append_newline = True
            merged = merged + (f"{eng_font}" if merged == "" else "  ") + line
    return merged


def load_subtitles(source_sub_path: Path):
    pysrt = require_dependency("pysrt")
    encoding = detect_file_encoding(source_sub_path)
    raw = source_sub_path.read_text(encoding=encoding)
    if source_sub_path.suffix.lower() == ".ass":
        asstosrt = require_dependency("asstosrt")
        raw = asstosrt.convert(raw)
    return pysrt.from_string(raw)


def write_ass_from_subs(subs, template_path: Path, output_path: Path, transform_text) -> None:
    template = read_ass_template(template_path)
    with output_path.open("w", encoding="utf-8") as handle:
        handle.write(template)
        handle.write("\n\n[Events]\n")
        handle.write("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n\n")
        for sub in subs:
            text = transform_text(sub)
            handle.write(
                "Dialogue: 0,"
                f"{format_ass_timestamp(sub.start)},"
                f"{format_ass_timestamp(sub.end)},"
                f"Default,,0,0,0,,{text}\n"
            )


def rewrite_single_track_to_template_ass(
    source_sub_path: Path,
    template_path: Path,
    output_path: Path,
    split_zh_and_en_lines: bool,
    english_standalone_font: bool,
) -> None:
    subs = load_subtitles(source_sub_path)
    write_ass_from_subs(
        subs,
        template_path,
        output_path,
        lambda sub: convert_pyass_text(sub.text, split_zh_and_en_lines, english_standalone_font),
    )


def subrip_time_to_ms(value) -> int:
    return ((value.hours * 60 + value.minutes) * 60 + value.seconds) * 1000 + value.milliseconds


def merge_bilingual_text(zh_text: str, en_text: str | None, english_standalone_font: bool) -> str:
    zh_block = flatten_multiline_text(zh_text)
    if not en_text:
        return zh_block
    en_block = flatten_multiline_text(en_text)
    if not en_block:
        return zh_block
    english_prefix = r"{\rEng}" if english_standalone_font else ""
    return f"{zh_block}\\N{english_prefix}{en_block}"


def find_matching_english(zh_sub, eng_subs, start_index: int):
    zh_start = subrip_time_to_ms(zh_sub.start)
    zh_end = subrip_time_to_ms(zh_sub.end)
    tolerance_ms = 800

    while start_index < len(eng_subs):
        eng = eng_subs[start_index]
        if subrip_time_to_ms(eng.end) + tolerance_ms < zh_start:
            start_index += 1
            continue
        break

    best_match = None
    best_index = start_index
    best_gap = None
    for index in range(start_index, len(eng_subs)):
        eng = eng_subs[index]
        eng_start = subrip_time_to_ms(eng.start)
        eng_end = subrip_time_to_ms(eng.end)
        if eng_start - tolerance_ms > zh_end:
            break

        overlap = min(zh_end, eng_end) - max(zh_start, eng_start)
        if overlap < -tolerance_ms:
            continue

        gap = abs(zh_start - eng_start) + abs(zh_end - eng_end)
        if best_gap is None or gap < best_gap:
            best_gap = gap
            best_match = eng
            best_index = index

    return best_match, (best_index + 1 if best_match is not None else start_index)


def rewrite_bilingual_to_template_ass(
    zh_sub_path: Path,
    template_path: Path,
    output_path: Path,
    en_sub_path: Path | None = None,
    english_standalone_font: bool = True,
) -> None:
    zh_subs = load_subtitles(zh_sub_path)
    eng_subs = load_subtitles(en_sub_path) if en_sub_path else None
    english_cursor = 0

    def transform(sub):
        nonlocal english_cursor
        matched_english = None
        if eng_subs:
            matched_english, english_cursor = find_matching_english(sub, eng_subs, english_cursor)
        return merge_bilingual_text(
            sub.text,
            matched_english.text if matched_english else None,
            english_standalone_font,
        )

    write_ass_from_subs(zh_subs, template_path, output_path, transform)


def probe_subtitle_streams(video_path: Path) -> list[SubtitleStream]:
    result = run_command(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "s",
            "-show_entries",
            "stream=index,codec_name:stream_tags=language,title",
            "-of",
            "json",
            str(video_path),
        ]
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or "ffprobe failed")

    payload = json.loads(result.stdout or "{}")
    streams = []
    for subtitle_index, stream in enumerate(payload.get("streams", [])):
        tags = stream.get("tags", {})
        streams.append(
            SubtitleStream(
                stream_index=stream["index"],
                subtitle_index=subtitle_index,
                codec_name=stream.get("codec_name", "unknown"),
                language=tags.get("language", "und"),
                title=tags.get("title", ""),
            )
        )
    return streams


def print_streams(streams: list[SubtitleStream]) -> None:
    for stream in streams:
        print(describe_stream(stream))


def is_chinese_stream(stream: SubtitleStream) -> bool:
    language = normalize_language(stream.language)
    title = normalize_language(stream.title)
    return (
        language in {"chi", "zho", "zh", "chs", "cn", "sc"}
        or "简" in stream.title
        or "chs" in title
        or "simplified" in title
    )


def is_simplified_chinese_stream(stream: SubtitleStream) -> bool:
    language = normalize_language(stream.language)
    title = normalize_language(stream.title)
    raw_title = stream.title
    return (
        language in {"chs", "cn", "sc"}
        or "简" in raw_title
        or "简中" in raw_title
        or "简体" in raw_title
        or "chs" in title
        or "gb" in title
        or "sc" == title
        or "simplified" in title
    )


def is_english_stream(stream: SubtitleStream) -> bool:
    language = normalize_language(stream.language)
    title = normalize_language(stream.title)
    return language in {"eng", "en"} or "english" in title or title == "eng"


def english_stream_priority(stream: SubtitleStream) -> tuple[int, int]:
    title = normalize_language(stream.title)
    if not is_english_stream(stream):
        return (99, stream.subtitle_index)
    if "forced" in title:
        return (3, stream.subtitle_index)
    if "sdh" in title or "cc" in title:
        return (1, stream.subtitle_index)
    return (0, stream.subtitle_index)


def get_stream_by_index(streams: list[SubtitleStream], subtitle_index: int) -> SubtitleStream:
    if subtitle_index < 0 or subtitle_index >= len(streams):
        raise SystemExit(f"无效的字幕流编号: {subtitle_index}")
    return streams[subtitle_index]


def pick_auto_streams(streams: list[SubtitleStream]) -> tuple[SubtitleStream, SubtitleStream | None]:
    text_streams = [stream for stream in streams if stream.codec_name.lower() in TEXT_SUBTITLE_CODECS]
    if not text_streams:
        raise SystemExit(
            "没有找到可转换的文本字幕流；当前文件只有图片字幕（例如 PGS/SUP），"
            "q-xsub 目前不支持这类字幕，请先用 `list-streams` 确认。"
        )
    zh_stream = next((stream for stream in text_streams if is_simplified_chinese_stream(stream)), None)
    if zh_stream is None:
        zh_stream = next((stream for stream in text_streams if is_chinese_stream(stream)), None)
    if zh_stream is None:
        raise SystemExit(
            "没有找到可转换的中文字幕文本流；请先用 `list-streams` 查看字幕类型和语言标签，"
            "再决定是否手动指定。"
        )
    english_candidates = [
        stream
        for stream in text_streams
        if stream.subtitle_index != zh_stream.subtitle_index and is_english_stream(stream)
    ]
    en_stream = min(english_candidates, key=english_stream_priority) if english_candidates else None
    return zh_stream, en_stream


def extract_subtitle_stream(video_path: Path, stream: SubtitleStream, workdir: Path) -> Path:
    codec = stream.codec_name.lower()
    if codec not in TEXT_SUBTITLE_CODECS:
        raise SystemExit(f"字幕流 {stream.subtitle_index} 使用 {stream.codec_name}，不是可转换的文本字幕。")

    suffix = ".ass" if codec in {"ass", "ssa"} else ".srt"
    output_path = workdir / f"stream-{stream.subtitle_index}{suffix}"
    log(f"extracting: {video_path.name} -> {describe_stream(stream)}")
    result = run_command(
        [
            "ffmpeg",
            "-y",
            "-nostdin",
            "-loglevel",
            "error",
            "-i",
            str(video_path),
            "-map",
            f"0:s:{stream.subtitle_index}",
            str(output_path),
        ]
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or "ffmpeg failed")
    return output_path


def subtitle_output_path(stream: SubtitleStream, workdir: Path) -> Path:
    codec = stream.codec_name.lower()
    suffix = ".ass" if codec in {"ass", "ssa"} else ".srt"
    return workdir / f"stream-{stream.subtitle_index}{suffix}"


def extract_subtitle_streams(video_path: Path, streams: list[SubtitleStream], workdir: Path) -> dict[int, Path]:
    if not streams:
        return {}

    cmd = ["ffmpeg", "-y", "-nostdin", "-loglevel", "error", "-i", str(video_path)]
    output_paths: dict[int, Path] = {}
    selected = ", ".join(describe_stream(stream) for stream in streams)
    log(f"extracting: {video_path.name} -> {selected}")

    for stream in streams:
        codec = stream.codec_name.lower()
        if codec not in TEXT_SUBTITLE_CODECS:
            raise SystemExit(f"字幕流 {stream.subtitle_index} 使用 {stream.codec_name}，不是可转换的文本字幕。")

        output_path = subtitle_output_path(stream, workdir)
        output_paths[stream.subtitle_index] = output_path
        cmd.extend(["-map", f"0:s:{stream.subtitle_index}", str(output_path)])

    result = run_command(cmd)
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or "ffmpeg failed")
    return output_paths


def default_output_path(input_path: Path, output: str | None, suffix: str = ".ass") -> Path:
    if output:
        return Path(output).expanduser().resolve()
    return input_path.with_suffix(suffix)


def handle_list_templates(_args: argparse.Namespace) -> int:
    templates = list_builtin_templates()
    if not templates:
        print("没有找到内置模板。", file=sys.stderr)
        return 1
    for template in templates:
        print(template)
    return 0


def handle_list_streams(args: argparse.Namespace) -> int:
    video_path = Path(args.input).expanduser().resolve()
    if not video_path.exists():
        raise SystemExit(f"输入文件不存在: {video_path}")
    ensure_tool_installed("ffprobe")
    streams = probe_subtitle_streams(video_path)
    if not streams:
        print("没有找到字幕流。", file=sys.stderr)
        return 1
    print_streams(streams)
    return 0


def handle_convert(args: argparse.Namespace) -> int:
    template_path = resolve_template_path(args.template)
    if args.output and len(args.files) > 1:
        raise SystemExit("convert 使用 -o 时只能处理单个输入文件。")

    for source in args.files:
        source_path = Path(source).expanduser().resolve()
        if source_path.suffix.lower() not in {".srt", ".ass"}:
            print(f"ignore unsupported file: {source_path}", file=sys.stderr)
            continue
        output_path = default_output_path(source_path, args.output if len(args.files) == 1 else None)
        rewrite_single_track_to_template_ass(
            source_path,
            template_path,
            output_path,
            split_zh_and_en_lines=args.split_zh_and_en_lines,
            english_standalone_font=args.english_standalone_font,
        )
        print(f"written: {output_path}")
    return 0


def handle_extract(args: argparse.Namespace) -> int:
    if args.output and len(args.inputs) > 1:
        raise SystemExit("extract 使用 -o 时只能处理单个输入文件。")

    ensure_tool_installed("ffprobe")
    ensure_tool_installed("ffmpeg")
    template_path = resolve_template_path(args.template)
    for source in args.inputs:
        video_path = Path(source).expanduser().resolve()
        if not video_path.exists():
            raise SystemExit(f"输入文件不存在: {video_path}")

        log(f"processing: {video_path}")
        streams = probe_subtitle_streams(video_path)
        if not streams:
            raise SystemExit("没有找到字幕流。")
        log(f"probed: found {len(streams)} subtitle streams")

        with tempfile.TemporaryDirectory(prefix="q-xsub-") as tempdir:
            tempdir_path = Path(tempdir)
            output_path = default_output_path(video_path, args.output if len(args.inputs) == 1 else None)

            if args.stream is not None:
                stream = get_stream_by_index(streams, args.stream)
                log(f"selected: manual stream {describe_stream(stream)}")
                extracted_path = extract_subtitle_stream(video_path, stream, tempdir_path)
                log(f"rewriting: single-track -> {output_path} using template {template_path.name}")
                rewrite_single_track_to_template_ass(
                    extracted_path,
                    template_path,
                    output_path,
                    split_zh_and_en_lines=args.split_zh_and_en_lines,
                    english_standalone_font=args.english_standalone_font,
                )
            else:
                zh_stream, en_stream = pick_auto_streams(streams)
                log(f"selected: zh {describe_stream(zh_stream)}")
                if en_stream:
                    log(f"selected: en {describe_stream(en_stream)}")
                else:
                    log("selected: no English subtitle stream")
                streams_to_extract = [zh_stream]
                if en_stream:
                    streams_to_extract.append(en_stream)
                extracted_paths = extract_subtitle_streams(video_path, streams_to_extract, tempdir_path)
                zh_sub_path = extracted_paths[zh_stream.subtitle_index]
                en_sub_path = extracted_paths.get(en_stream.subtitle_index) if en_stream else None
                log(f"rewriting: bilingual -> {output_path} using template {template_path.name}")
                rewrite_bilingual_to_template_ass(
                    zh_sub_path,
                    template_path,
                    output_path,
                    en_sub_path=en_sub_path,
                    english_standalone_font=args.english_standalone_font,
                )

        print(f"written: {output_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="q-xsub",
        description="提取 MKV 内置字幕，并按 pyass 模板重建 ASS 样式。",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_templates_parser = subparsers.add_parser("list-templates", help="列出可用模板")
    list_templates_parser.set_defaults(handler=handle_list_templates)

    list_streams_parser = subparsers.add_parser("list-streams", help="列出 MKV 中的字幕流")
    list_streams_parser.add_argument("input", help="输入 MKV 文件路径")
    list_streams_parser.set_defaults(handler=handle_list_streams)

    convert_parser = subparsers.add_parser("convert", help="将 .srt/.ass 按模板转换成 ASS")
    convert_parser.add_argument("files", nargs="+", help="输入字幕文件，支持 .srt 和 .ass")
    convert_parser.add_argument("-o", "--output", help="输出 ASS 文件路径，仅单文件转换时可用")
    convert_parser.add_argument(
        "-t",
        "--template",
        default="1",
        help="模板名或模板 ASS 文件路径，默认使用当前仓库 template/1.ass",
    )
    convert_parser.add_argument(
        "-s",
        "--split-zh-and-en-lines",
        action="store_true",
        help="将单轨中英混合字幕拆成中文在上、英文在下",
    )
    convert_parser.add_argument(
        "--no-english-standalone-font",
        dest="english_standalone_font",
        action="store_false",
        help="关闭英文行的 Eng 样式；默认开启",
    )
    convert_parser.set_defaults(english_standalone_font=True)
    convert_parser.set_defaults(handler=handle_convert)

    extract_parser = subparsers.add_parser("extract", help="从 MKV 提取字幕并生成模板 ASS")
    extract_parser.add_argument("inputs", nargs="+", help="一个或多个输入 MKV 文件路径")
    extract_parser.add_argument("-o", "--output", help="输出 ASS 文件路径，仅单文件提取时可用")
    extract_parser.add_argument(
        "-t",
        "--template",
        default="1",
        help="模板名或模板 ASS 文件路径，默认使用当前仓库 template/1.ass",
    )
    extract_parser.add_argument(
        "--stream",
        type=int,
        help="手动指定单个字幕流编号；不指定时默认自动提取简中并叠加英文",
    )
    extract_parser.add_argument(
        "-s",
        "--split-zh-and-en-lines",
        action="store_true",
        help="仅对 --stream 单轨提取生效：将中英混合字幕拆成中文在上、英文在下",
    )
    extract_parser.add_argument(
        "--no-english-standalone-font",
        dest="english_standalone_font",
        action="store_false",
        help="关闭英文行的 Eng 样式；默认开启，在单轨和双流输出中都生效",
    )
    extract_parser.set_defaults(english_standalone_font=True)
    extract_parser.set_defaults(handler=handle_extract)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    raise SystemExit(args.handler(args))


if __name__ == "__main__":
    main()
