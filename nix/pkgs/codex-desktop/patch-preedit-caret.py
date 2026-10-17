#!/usr/bin/env python3
"""修复 Codex 组合输入首字母的光标位置（2026-10-17 本机实测有效）。

环境：Codex 26.1007.71326，NixOS / GNOME 50.5 Wayland，fcitx5 + WeTypeX；
WeTypeX 开启默认的 preedit_cursor_at_beginning（候选框固定在拼音起始位置）。
现象：输入 f 时光标在 f 后，追加 s 后才跳到整段 preedit 前，候选框也随之跳动。
实际抓取桌面 IBus 信号，f 和 f's 的 cursor 都是 0；输入法从首键就请求放在开头。

根因：内置 ProseMirror 在 Chromium 组字期间会丢弃位于文本变更起点的 DOM selection。
首键时变更起点恰好等于 preedit 起点，请求的 selection 被忽略，插入事务把光标映射
到字母后；第二键追加文本的变更起点已在首字母后，preedit 起点才被正常接受。
这里让变更起点的 selection 通过，保留 Chromium 的其他过滤条件及 IE 分支。
这是本地兼容补丁，未确认上游是否已有修复，不需要修改输入法的光标策略。

实现：仅等长修改两个运算符（实际改变 3 个字节），保持 ASAR 文件大小与偏移不变，
并更新该 JS 资源的 SHA256 整体和分块校验。正则捕获压缩变量名，不写死资源哈希。
升级时若不能唯一匹配旧逻辑，直接让构建失败；应重新检查上游代码，不要放宽匹配。
移除补丁前，用未打补丁的新版本复测首键、追加、退格和选词，确认已无需本补丁。
"""

import argparse
import hashlib
import json
import mmap
import re
import struct
from pathlib import Path


CHROME_SELECTION = re.compile(
    rb"[\w$]+&&(?P<view>[\w$]+)\.composing&&(?P<sel>[\w$]+)\.empty&&"
    rb"\((?P<diff>[\w$]+)\.start!=(?P=diff)\.endB\|\|"
    rb"(?P=view)\.input\.lastChromeDelete<Date\.now\(\)-100\)&&"
    rb"(?P<clause>\((?P=sel)\.head==(?P<start>[\w$]+)\|\|"
    rb"(?P=sel)\.head==[\w$]+\.mapping\.map\([\w$]+\)-1\))"
)


def patch(archive: Path) -> None:
    with archive.open("r+b") as file, mmap.mmap(file.fileno(), 0) as data:
        _, header_size, _, json_size = struct.unpack_from("<4I", data)
        header = json.loads(data[16 : 16 + json_size])
        payload = 8 + header_size
        assets = header["files"]["webview"]["files"]["assets"]["files"]
        matches = []
        for name, entry in assets.items():
            if not (name.startswith("app-shared-") and name.endswith(".js")):
                continue
            if entry.get("unpacked"):
                raise ValueError(f"unexpected unpacked asset: {name}")
            offset = payload + int(entry["offset"])
            content = data[offset : offset + entry["size"]]
            for match in CHROME_SELECTION.finditer(content):
                matches.append((name, entry, offset, content, match))
        if len(matches) != 1:
            raise ValueError(f"expected one ProseMirror caret guard, found {len(matches)}")
        name, entry, offset, content, match = matches[0]
        clause = match["clause"]
        # (sel.head == start || atEndMinusOne) ->
        # (sel.head != start && atEndMinusOne). Both operators keep their length.
        # 不能只删除左侧条件：首字母时 start 同时也是映射后的末尾减一，仍会被过滤。
        replacement = clause.replace(b"==", b"!=", 1).replace(b"||", b"&&", 1)
        start, end = match.span("clause")
        content = content[:start] + replacement + content[end:]
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
        new_header = json.dumps(header, ensure_ascii=False, separators=(",", ":")).encode()
        if len(new_header) != json_size:
            raise ValueError("ASAR header size changed; refusing to alter file offsets")
        # Validate everything before writing either the code or header.
        data[offset + start : offset + end] = replacement
        data[16 : 16 + json_size] = new_header
        data.flush()
        print(f"Patched preedit caret guard in {name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("asar", type=Path)
    patch(parser.parse_args().asar)
