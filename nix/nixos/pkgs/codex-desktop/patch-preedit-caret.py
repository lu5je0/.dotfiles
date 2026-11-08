#!/usr/bin/env python3
"""修复 Codex 在 GNOME Wayland + Fcitx5 / WeTypeX 下的组合输入。

适用配置：WeTypeX 开启 preedit_cursor_at_beginning，候选框固定在拼音起点。
ProseMirror 的 Chromium selection 过滤会丢弃位于文本变更起点的光标，
因此保留起点 selection，仅保留其他 Chromium 过滤条件与 IE 分支。

失焦时的自动补字与输入法的组字首键可能重叠；自动聚焦只负责获取焦点，
字符交给浏览器和输入法。发送后的过渡层可能仍带 inert，聚焦失败时限时重试，
但用户主动聚焦其他控件后必须放弃，不能抢回焦点。

输入预测插件只在 keyCode=229 时提前隐藏提示，无法覆盖直接到达的 compositionstart。
在组字开始时隐藏预测，并按上述光标策略校正隐藏预测后的第一段 preedit。
运行时处理与监听的生命周期见 ime-workarounds.js，不依赖调试端口。

递归匹配 JS 资源中的四处逻辑，捕获压缩变量名，不写死资源哈希。
升级时若不能唯一匹配，构建直接失败，应检查上游代码而非放宽匹配。
资源增长时重算 ASAR 偏移、大小与 SHA256 整体及分块校验，保留其他资源内容，
通过临时文件原子替换归档，避免失败时留下不完整文件。
移除补丁前，用原版复测首键、追加、退格、选词、输入预测与发送后立即输入。
"""

import argparse
import hashlib
import json
import mmap
import os
import re
import struct
import tempfile
from pathlib import Path


CHROME_SELECTION = re.compile(
    rb"[\w$]+&&(?P<view>[\w$]+)\.composing&&(?P<sel>[\w$]+)\.empty&&"
    rb"\((?P<diff>[\w$]+)\.start!=(?P=diff)\.endB\|\|"
    rb"(?P=view)\.input\.lastChromeDelete<Date\.now\(\)-100\)&&"
    rb"(?P<clause>\((?P=sel)\.head==(?P<start>[\w$]+)\|\|"
    rb"(?P=sel)\.head==[\w$]+\.mapping\.map\([\w$]+\)-1\))"
)
AUTO_FOCUS = re.compile(
    rb"(?P<event>[\w$]+)\.preventDefault\(\),"
    rb"(?P<controller>[\w$]+)\.insertTextAtSelection\((?P=event)\.key\)"
)
PREDICTION_PLUGIN = re.compile(
    rb"(?P<plugin>new [\w$]+\(\{key:[\w$]+,state:\{init:\(\)=>null,"
    rb"apply\([\w$]+,[\w$]+\)\{[^\n]*?hiddenForComposition:[^\n]*?\}\}\}\))"
    rb"(?=\}function )"
)
COMPOSER_FOCUS = re.compile(
    rb"focus\((?P<position>[\w$]+)\)\{if\((?P=position)===`end`\)\{"
    rb"let\{state:(?P<state>[\w$]+)\}=this\.view;this\.view\.dispatch\("
    rb"(?P=state)\.tr\.setSelection\([\w$]+\.atEnd\((?P=state)\.doc\)\)\)\}"
    rb"this\.view\.editable\|\|this\.view\.dom\.focus\(\{preventScroll:!0\}\),"
    rb"(?P<call>this\.view\.focus\(\))\}"
)


def iter_files(files: dict, prefix: str = ""):
    for name, entry in files.items():
        path = prefix + name
        if "files" in entry:
            yield from iter_files(entry["files"], path + "/")
        else:
            yield path, entry


def copy_range(source, target, start: int, end: int) -> None:
    source.seek(start)
    remaining = end - start
    while remaining:
        chunk = source.read(min(remaining, 1024 * 1024))
        if not chunk:
            raise ValueError("truncated ASAR payload")
        target.write(chunk)
        remaining -= len(chunk)


def patch(archive: Path, helpers: Path) -> None:
    runtime = helpers.read_bytes()
    with archive.open("rb") as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as data:
        _, header_size, _, json_size = struct.unpack_from("<4I", data)
        header = json.loads(data[16 : 16 + json_size])
        payload = 8 + header_size
        resources = list(iter_files(header["files"]))
        packed = sorted(
            (int(entry["offset"]), entry["size"], name, entry)
            for name, entry in resources
            if not entry.get("unpacked") and "link" not in entry
        )
        previous_end = 0
        ranges = {}
        for offset, size, name, _ in packed:
            # ASAR 可让内容相同的文件共享区间，例如重复打包的 LICENSE。
            if (offset, size) in ranges:
                ranges[offset, size].append(name)
                continue
            if offset < previous_end or size < 0 or payload + offset + size > len(data):
                raise ValueError(f"invalid ASAR resource range: {name}")
            ranges[offset, size] = [name]
            previous_end = offset + size

        matches = {key: [] for key in ("caret", "auto-focus", "prediction", "focus-retry")}
        for name, entry in resources:
            if not name.startswith("webview/assets/") or not name.endswith(".js") or "link" in entry:
                continue
            if entry.get("unpacked"):
                raise ValueError(f"unexpected unpacked asset: {name}")
            offset = payload + int(entry["offset"])
            content = data[offset : offset + entry["size"]]
            if b"codexImePredictionPlugin" in content or b"codexImeFocus" in content:
                raise ValueError(f"asset already contains IME helpers: {name}")
            if b"lastChromeDelete" in content:
                matches["caret"].extend((name, entry, content, m) for m in CHROME_SELECTION.finditer(content))
            # 限定扫描窗口，避免在无关长字符串上回溯压缩变量名。
            for call in re.finditer(rb"\.insertTextAtSelection\(", content):
                for match in AUTO_FOCUS.finditer(content, max(0, call.start() - 100), call.start() + 100):
                    if match.start() < call.start() < match.end():
                        matches["auto-focus"].append((name, entry, content, match))
            for marker in re.finditer(rb"hiddenForComposition:", content):
                for match in PREDICTION_PLUGIN.finditer(content, max(0, marker.start() - 300), marker.start() + 5000):
                    if match.start() < marker.start() < match.end():
                        matches["prediction"].append((name, entry, content, match))
            if b"this.view.dom.focus({preventScroll:!0})" in content:
                matches["focus-retry"].extend((name, entry, content, m) for m in COMPOSER_FOCUS.finditer(content))
        for kind, found in matches.items():
            if len(found) != 1:
                raise ValueError(f"expected one {kind} patch target, found {len(found)}")

        replacements = {}
        helper_assets = set()

        def edit(target, replacement: bytes, group=0, needs_helpers=False):
            name, entry, content, match = target
            _, _, edits = replacements.setdefault(name, (entry, content, []))
            edits.append((*match.span(group), replacement))
            if needs_helpers:
                helper_assets.add(name)

        caret = matches["caret"][0][3]["clause"]
        # 起点同时可能等于映射后的末尾减一，不能只删除左侧条件。
        edit(matches["caret"][0], caret.replace(b"==", b"!=", 1).replace(b"||", b"&&", 1), "clause")
        edit(matches["auto-focus"][0], matches["auto-focus"][0][3]["controller"] + b".focus()")
        plugin = matches["prediction"][0][3]["plugin"]
        edit(matches["prediction"][0], b"codexImePredictionPlugin(" + plugin + b")", "plugin", True)
        edit(matches["focus-retry"][0], b"codexImeFocus(this.view)", "call", True)

        patched_assets = {}
        for name, (entry, content, edits) in replacements.items():
            previous_start = len(content)
            for start, end, replacement in sorted(edits, reverse=True):
                if end > previous_start:
                    raise ValueError(f"overlapping patches: {name}")
                content = content[:start] + replacement + content[end:]
                previous_start = start
            if name in helper_assets:
                content += b"\n" + runtime + b"\n"
            integrity = entry.get("integrity")
            if integrity:
                if integrity["algorithm"] != "SHA256" or integrity["blockSize"] <= 0:
                    raise ValueError("unsupported ASAR integrity metadata")
                block_size = integrity["blockSize"]
                integrity["hash"] = hashlib.sha256(content).hexdigest()
                integrity["blocks"] = [
                    hashlib.sha256(content[i : i + block_size]).hexdigest()
                    for i in range(0, len(content), block_size)
                ]
            patched_assets[name] = content

        for names in ranges.values():
            if len(names) > 1 and any(name in patched_assets for name in names):
                raise ValueError("patch target shares a payload range: " + ", ".join(names))
        delta = 0
        for offset, size, name, entry in packed:
            entry["offset"] = str(offset + delta)
            if name in patched_assets:
                entry["size"] = len(patched_assets[name])
                delta += entry["size"] - size
        new_header = json.dumps(header, ensure_ascii=False, separators=(",", ":")).encode()
        padding = b"\0" * (-len(new_header) % 4)
        new_header_size = len(new_header) + len(padding) + 8
        with tempfile.NamedTemporaryFile(dir=archive.parent, delete=False) as output:
            temporary = Path(output.name)
            try:
                os.fchmod(output.fileno(), archive.stat().st_mode & 0o777)
                output.write(struct.pack("<4I", 4, new_header_size, new_header_size - 4, len(new_header)))
                output.write(new_header)
                output.write(padding)
                cursor = payload
                for offset, size, name, _ in packed:
                    if name not in patched_assets:
                        continue
                    copy_range(file, output, cursor, payload + offset)
                    output.write(patched_assets[name])
                    cursor = payload + offset + size
                copy_range(file, output, cursor, len(data))
                output.flush()
                os.replace(temporary, archive)
            finally:
                temporary.unlink(missing_ok=True)
        print("Patched IME caret, auto-focus, prediction and focus retry in " + ", ".join(replacements))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helpers", type=Path, required=True)
    parser.add_argument("asar", type=Path)
    args = parser.parse_args()
    patch(args.asar, args.helpers)
