import argparse
import mimetypes
import os
import re
import sys
from pathlib import Path

import requests

TELEGRAM_TEXT_LIMIT = 4000
TELEGRAM_CAPTION_LIMIT = 1000
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"}
FORMATS = ("text", "markdown", "html")
TARGETS = ("telegram", "feishu", "all")


class PushError(Exception):
    """推送失败，由 main 统一转成非零退出码。"""


def escape_telegram_markdown_v2(text: str):
    return re.sub(r"([_*\[\]()~`>#+\-=|{}.!\\])", r"\\\1", text)


def escape_telegram_code(text: str):
    return text.replace("\\", "\\\\").replace("`", "\\`")


def convert_inline_markdown_to_telegram(text: str):
    parts = []
    index = 0
    pattern = re.compile(r"(`([^`]+)`)|(\*\*([^*]+)\*\*)")

    for match in pattern.finditer(text):
        start, end = match.span()
        if start > index:
            parts.append(escape_telegram_markdown_v2(text[index:start]))

        if match.group(1):
            parts.append(f"`{escape_telegram_code(match.group(2))}`")
        else:
            parts.append(f"*{escape_telegram_markdown_v2(match.group(4))}*")

        index = end

    if index < len(text):
        parts.append(escape_telegram_markdown_v2(text[index:]))

    return "".join(parts)


def convert_markdown_to_telegram(text: str):
    result = []
    in_code_block = False
    code_block_lang = ""
    code_lines = []

    for line in text.splitlines():
        fence = re.match(r"^```(\w+)?\s*$", line)
        if fence:
            if in_code_block:
                if code_block_lang:
                    result.append(f"```{code_block_lang}")
                else:
                    result.append("```")
                result.extend(escape_telegram_code(code_line) for code_line in code_lines)
                result.append("```")
                code_lines = []
                code_block_lang = ""
                in_code_block = False
            else:
                in_code_block = True
                code_block_lang = fence.group(1) or ""
            continue

        if in_code_block:
            code_lines.append(line)
            continue

        heading = re.match(r"^(#{1,6})\s+(.*)$", line)
        if heading:
            result.append(f"*{escape_telegram_markdown_v2(heading.group(2).strip())}*")
            continue

        bullet = re.match(r"^(\s*)[-*]\s+(.*)$", line)
        if bullet:
            indent = "  " * (len(bullet.group(1)) // 2)
            result.append(f"{indent}• {convert_inline_markdown_to_telegram(bullet.group(2))}")
            continue

        ordered = re.match(r"^(\s*)(\d+)\.\s+(.*)$", line)
        if ordered:
            indent = "  " * (len(ordered.group(1)) // 2)
            number = escape_telegram_markdown_v2(ordered.group(2) + ".")
            result.append(f"{indent}{number} {convert_inline_markdown_to_telegram(ordered.group(3))}")
            continue

        result.append(convert_inline_markdown_to_telegram(line))

    if in_code_block:
        if code_block_lang:
            result.append(f"```{code_block_lang}")
        else:
            result.append("```")
        result.extend(escape_telegram_code(code_line) for code_line in code_lines)
        result.append("```")

    return "\n".join(result)


def split_telegram_text(text: str, limit: int = TELEGRAM_TEXT_LIMIT):
    """按行切分超长文本，避免 Telegram 400 报错。"""
    if len(text) <= limit:
        return [text]

    chunks = []
    current = ""
    for line in text.splitlines(keepends=True):
        if current and len(current) + len(line) > limit:
            chunks.append(current)
            current = ""
        while len(line) > limit:
            chunks.append(line[:limit])
            line = line[limit:]
        current += line

    if current:
        chunks.append(current.rstrip("\n") if len(chunks) else current)
    return chunks


def parse_telegram_bot(value: str):
    value = value.strip()
    if value == "":
        return None, None

    token, sep, chat_id = value.partition(",")
    if sep == "":
        print("telegram config is invalid: TELEGRAM_PUSH_CONFIG, expected '<token>,<chat_id>'")
        sys.exit(1)

    token = token.strip()
    chat_id = chat_id.strip()
    if token == "" or chat_id == "":
        print("telegram config is invalid: TELEGRAM_PUSH_CONFIG, expected '<token>,<chat_id>'")
        sys.exit(1)

    return token, chat_id


def telegram_parse_mode(fmt: str):
    return {"markdown": "MarkdownV2", "html": "HTML"}.get(fmt)


def load_attachments(files):
    """把命令行里的文件路径解析成 (name, bytes, mimetype) 列表，支持 '-' 读 stdin。"""
    attachments = []
    stdin_used = False

    for raw in files:
        if raw == "-":
            if stdin_used:
                raise PushError("stdin can only be attached once: -F -")
            data = sys.stdin.buffer.read()
            stdin_used = True
            attachments.append(("stdin.txt", data, "text/plain"))
            continue

        path = Path(raw).expanduser()
        if not path.is_file():
            raise PushError(f"file not found: {raw}")
        mime, _ = mimetypes.guess_type(path.name)
        attachments.append((path.name, path.read_bytes(), mime or "application/octet-stream"))

    return attachments, stdin_used


def push_feishu(text: str, fmt: str = "text", attachments=()):
    if fmt != "text":
        raise PushError(f"feishu only supports plain text, got format: {fmt}")
    if attachments:
        raise PushError("feishu does not support file attachments")

    token = os.environ.get("FEISHU_TOKEN", "").strip()
    if token == "":
        return False

    try:
        resp = requests.post(
            "https://open.feishu.cn/open-apis/bot/v2/hook/" + token,
            headers={"Content-Type": "application/json"},
            json={
                "msg_type": "text",
                "content": {
                    "text": text,
                },
            },
            timeout=30,
        )
    except requests.RequestException as exc:
        raise PushError(f"feishu push failed: {exc}") from exc

    if resp.status_code != 200:
        raise PushError(f"feishu push failed {resp.status_code}: {resp.text}")

    return True


def push_telegram(text: str, fmt: str = "text", attachments=()):
    token, chat_id = parse_telegram_bot(os.environ.get("TELEGRAM_PUSH_CONFIG", ""))
    if token is None:
        return False

    base = f"https://api.telegram.org/bot{token}"
    parse_mode = telegram_parse_mode(fmt)

    if fmt == "markdown":
        text = convert_markdown_to_telegram(text)

    caption = text if text.strip() else None
    if caption and len(caption) > TELEGRAM_CAPTION_LIMIT:
        caption = caption[: TELEGRAM_CAPTION_LIMIT - 1] + "…"

    if text.strip():
        chunks = split_telegram_text(text)
        for index, chunk in enumerate(chunks, start=1):
            if len(chunks) > 1:
                chunk = f"[{index}/{len(chunks)}]\n{chunk}"
            payload = {"chat_id": chat_id, "text": chunk, "disable_web_page_preview": True}
            if parse_mode:
                payload["parse_mode"] = parse_mode
            try:
                resp = requests.post(f"{base}/sendMessage", json=payload, timeout=30)
            except requests.RequestException as exc:
                raise PushError(f"telegram push failed: {exc}") from exc
            if resp.status_code != 200:
                raise PushError(f"telegram push failed {resp.status_code}: {resp.text}")

    for index, (name, data, mime) in enumerate(attachments):
        is_photo = Path(name).suffix.lower() in IMAGE_SUFFIXES and mime.startswith("image/")
        method = "sendPhoto" if is_photo else "sendDocument"
        field = "photo" if is_photo else "document"

        form = {"chat_id": chat_id}
        if index == 0 and caption:
            form["caption"] = caption
            if parse_mode:
                form["parse_mode"] = parse_mode

        try:
            resp = requests.post(
                f"{base}/{method}",
                data=form,
                files={field: (name, data, mime)},
                timeout=120,
            )
        except requests.RequestException as exc:
            raise PushError(f"telegram {method} failed for {name}: {exc}") from exc
        if resp.status_code != 200:
            raise PushError(f"telegram {method} failed {resp.status_code}: {resp.text}")

    return True


def push(text: str, target: str, fmt: str = "text", attachments=()):
    pushed = False

    if target == "feishu":
        pushed = push_feishu(text, fmt=fmt, attachments=attachments)
        if not pushed:
            raise PushError("push target is missing: FEISHU_TOKEN")
        return

    if target == "telegram":
        pushed = push_telegram(text, fmt=fmt, attachments=attachments)
        if not pushed:
            raise PushError("push target is missing: TELEGRAM_PUSH_CONFIG='<token>,<chat_id>'")
        return

    if target == "all":
        errors = []
        for one in ("feishu", "telegram"):
            try:
                if one == "feishu":
                    pushed = push_feishu(text, fmt=fmt, attachments=attachments) or pushed
                else:
                    pushed = push_telegram(text, fmt=fmt, attachments=attachments) or pushed
            except PushError as exc:
                errors.append(str(exc))
        if errors:
            raise PushError("; ".join(errors))

    if not pushed:
        raise PushError("push target is missing: FEISHU_TOKEN or TELEGRAM_PUSH_CONFIG='<token>,<chat_id>'")


def build_parser():
    parser = argparse.ArgumentParser(
        prog="q-push",
        description="push text, markdown or html to Feishu / Telegram",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "examples:\n"
            "  q-push hello world\n"
            "  q-push -t telegram -f markdown '*hi*'\n"
            "  q-push -t telegram -f html '<b>hi</b>'\n"
            "  q-push -t telegram -F report.html\n"
            "  echo hello | q-push\n"
        ),
    )
    parser.add_argument('msgs', nargs='*', help="message body, joined by newlines")
    parser.add_argument(
        "-t",
        "--target",
        choices=TARGETS,
        default="telegram",
        help="push target, default: telegram",
    )
    parser.add_argument(
        "-f",
        "--format",
        choices=FORMATS,
        default=None,
        help="payload format, default: text",
    )
    parser.add_argument(
        "-m",
        "--markdown",
        action="store_true",
        help="shorthand for --format markdown",
    )
    parser.add_argument(
        "-H",
        "--html",
        action="store_true",
        help="shorthand for --format html (telegram only)",
    )
    parser.add_argument(
        "-F",
        "--file",
        action="append",
        default=[],
        metavar="PATH",
        help="attach a file (repeatable, '-' reads stdin); images go as photo",
    )
    return parser


def resolve_format(args):
    chosen = [fmt for fmt, flag in (("markdown", args.markdown), ("html", args.html)) if flag]
    if args.format:
        chosen.append(args.format)
    if len(set(chosen)) > 1:
        raise PushError(f"conflicting format flags: {', '.join(sorted(set(chosen)))}")
    return chosen[0] if chosen else "text"


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        fmt = resolve_format(args)
        attachments, stdin_as_file = load_attachments(args.file)

        parts = []
        if args.msgs:
            parts.append("\n".join(args.msgs))
        if not sys.stdin.isatty() and not stdin_as_file:
            stdin_text = sys.stdin.read()
            if stdin_text:
                parts.append(stdin_text.rstrip("\n"))

        text = "\n\n".join(part for part in parts if part)

        if not text and not attachments:
            print("Error: at least one message or --file is required.")
            parser.print_usage(sys.stderr)
            return 1

        push(text, args.target, fmt=fmt, attachments=attachments)
    except PushError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
