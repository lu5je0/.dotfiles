#!/usr/bin/env python3
"""修复 Codex 组合输入的首字母光标位置与自动聚焦时重复插入首字母。

环境：Codex 26.1007.71326，NixOS / GNOME 50.5 Wayland，fcitx5 + WeTypeX；
WeTypeX 开启默认的 preedit_cursor_at_beginning（候选框固定在拼音起始位置）。
现象：输入 f 时光标在 f 后，追加 s 后才跳到整段 preedit 前，候选框也随之跳动。
实际抓取桌面 IBus 信号，f 和 f's 的 cursor 都是 0；输入法从首键就请求放在开头。

根因：内置 ProseMirror 在 Chromium 组字期间会丢弃位于文本变更起点的 DOM selection。
首键时变更起点恰好等于 preedit 起点，请求的 selection 被忽略，插入事务把光标映射
到字母后；第二键追加文本的变更起点已在首字母后，preedit 起点才被正常接受。
这里让变更起点的 selection 通过，保留 Chromium 的其他过滤条件及 IE 分支。
这是本地兼容补丁，未确认上游是否已有修复，不需要修改输入法的光标策略。

自动聚焦逻辑只检查 isComposing，漏掉 compositionstart 之前的组字首键。
输入框暂时失焦时，它手动插入首字母，随后输入法再次送来完整拼音，出现 xxian / x先。
首键可能带普通按键编号或 229，不能仅凭 keyCode 判断是否组字。
此时只聚焦输入框，保留默认按键行为，让浏览器和输入法提供实际字符。

修改用空格补齐原长度，保持 ASAR 大小与资源偏移，并更新资源的 SHA256 整体和分块校验。
全部校验后通过临时文件原子替换，避免失败时留下不完整的归档。
正则捕获压缩变量名，不写死资源哈希。
递归扫描 webview/assets 下的 JS，兼容顶层资源与 async 子目录中的分块。
升级时若不能唯一匹配旧逻辑，直接让构建失败；应重新检查上游代码，不要放宽匹配。
移除补丁前，用未打补丁的新版本复测首键、追加、退格和选词，确认已无需本补丁。
"""

import argparse
import hashlib
import json
import mmap
import os
import re
import shutil
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


def iter_js_assets(files: dict, prefix: str = ""):
    for name, entry in files.items():
        path = prefix + name
        if "files" in entry:
            yield from iter_js_assets(entry["files"], path + "/")
        elif name.endswith(".js"):
            yield path, entry


def patch(archive: Path) -> None:
    with archive.open("rb") as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as data:
        _, header_size, _, json_size = struct.unpack_from("<4I", data)
        header = json.loads(data[16 : 16 + json_size])
        payload = 8 + header_size
        assets = header["files"]["webview"]["files"]["assets"]["files"]
        matches = []
        focus_matches = []
        for name, entry in iter_js_assets(assets):
            if entry.get("unpacked"):
                raise ValueError(f"unexpected unpacked asset: {name}")
            offset = payload + int(entry["offset"])
            content = data[offset : offset + entry["size"]]
            if b"lastChromeDelete" in content:
                for match in CHROME_SELECTION.finditer(content):
                    matches.append((name, entry, content, match))
            # 只在调用附近匹配，避免在无关长字符串上回溯变量名。
            for call in re.finditer(rb"\.insertTextAtSelection\(", content):
                start = max(0, call.start() - 100)
                for match in AUTO_FOCUS.finditer(content, start, call.start() + 100):
                    if match.start() < call.start() < match.end():
                        focus_matches.append((name, entry, content, match))
        if len(matches) != 1:
            raise ValueError(f"expected one ProseMirror caret guard, found {len(matches)}")
        if len(focus_matches) != 1:
            raise ValueError(f"expected one composer auto-focus insertion, found {len(focus_matches)}")
        name, entry, content, match = matches[0]
        clause = match["clause"]
        # (sel.head == start || atEndMinusOne) ->
        # (sel.head != start && atEndMinusOne). Both operators keep their length.
        # 不能只删除左侧条件：首字母时 start 同时也是映射后的末尾减一，仍会被过滤。
        replacement = clause.replace(b"==", b"!=", 1).replace(b"||", b"&&", 1)
        start, end = match.span("clause")
        replacements = {name: (entry, content, [(start, end, replacement)])}
        focus_name, focus_entry, focus_content, focus_match = focus_matches[0]
        focus_replacement = focus_match["controller"] + b".focus()"
        if len(focus_replacement) > len(focus_match[0]):
            raise ValueError("auto-focus replacement exceeds the original byte length")
        focus_replacement = focus_replacement.ljust(len(focus_match[0]), b" ")
        _, _, edits = replacements.setdefault(focus_name, (focus_entry, focus_content, []))
        edits.append((*focus_match.span(), focus_replacement))
        patched_assets = []
        for entry, content, edits in replacements.values():
            for start, end, replacement in sorted(edits, reverse=True):
                content = content[:start] + replacement + content[end:]
            if len(content) != entry["size"]:
                raise ValueError("patched resource size changed")
            integrity = entry.get("integrity")
            if integrity:
                if integrity["algorithm"] != "SHA256":
                    raise ValueError("unsupported ASAR integrity algorithm")
                block_size = integrity["blockSize"]
                integrity["hash"] = hashlib.sha256(content).hexdigest()
                integrity["blocks"] = [
                    hashlib.sha256(content[i : i + block_size]).hexdigest()
                    for i in range(0, len(content), block_size)
                ]
            patched_assets.append((payload + int(entry["offset"]), content))
        new_header = json.dumps(header, ensure_ascii=False, separators=(",", ":")).encode()
        if len(new_header) != json_size:
            raise ValueError("ASAR header size changed; refusing to alter file offsets")
        with tempfile.NamedTemporaryFile(dir=archive.parent, delete=False) as output:
            temporary = Path(output.name)
            try:
                os.fchmod(output.fileno(), archive.stat().st_mode & 0o777)
                file.seek(0)
                shutil.copyfileobj(file, output)
                output.seek(16)
                output.write(new_header)
                for offset, content in patched_assets:
                    output.seek(offset)
                    output.write(content)
                output.flush()
                os.replace(temporary, archive)
            finally:
                temporary.unlink(missing_ok=True)
        print(f"Patched preedit caret guard in {name} and IME auto-focus in {focus_name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("asar", type=Path)
    patch(parser.parse_args().asar)
