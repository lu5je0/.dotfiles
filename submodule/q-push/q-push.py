import argparse
import os
import re
import sys

import requests


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


def push_feishu(text: str, markdown: bool = False):
    token = os.environ.get("FEISHU_TOKEN", "").strip()
    if token == "":
        return False

    if markdown:
        print("feishu markdown is not supported")
        sys.exit(1)

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
        )
    except requests.RequestException as exc:
        print(f"feishu push failed: {exc}")
        return True

    if resp.status_code != 200:
        print("feishu push failed", resp)

    return True


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


def push_telegram(text: str, markdown: bool = False):
    token, chat_id = parse_telegram_bot(os.environ.get("TELEGRAM_PUSH_CONFIG", ""))
    if token is None:
        return False

    payload = {
        "chat_id": chat_id,
        "text": text,
    }
    if markdown:
        payload["parse_mode"] = "MarkdownV2"
        payload["text"] = convert_markdown_to_telegram(text)

    try:
        resp = requests.post(
            f"https://api.telegram.org/bot{token}/sendMessage",
            json=payload,
        )
    except requests.RequestException as exc:
        print(f"telegram push failed: {exc}")
        return True

    if resp.status_code != 200:
        print(f"telegram push failed {resp}: {resp.text}")

    return True


def push(text: str, target: str, markdown: bool = False):
    pushed = False

    if target == "feishu":
        pushed = push_feishu(text, markdown=markdown)
        if not pushed:
            print("push target is missing: FEISHU_TOKEN")
            sys.exit(1)
        return

    if target == "telegram":
        pushed = push_telegram(text, markdown=markdown)
        if not pushed:
            print("push target is missing: TELEGRAM_PUSH_CONFIG='<token>,<chat_id>'")
            sys.exit(1)
        return

    if target == "all":
        pushed = push_feishu(text, markdown=markdown) or pushed
        pushed = push_telegram(text, markdown=markdown) or pushed

    if not pushed:
        print("push target is missing: FEISHU_TOKEN or TELEGRAM_PUSH_CONFIG='<token>,<chat_id>'")
        sys.exit(1)

if __name__ == "__main__":
    text = ""
    
    parser = argparse.ArgumentParser()
    parser.add_argument('msgs', nargs='*')
    parser.add_argument(
        "-t",
        "--target",
        choices=["feishu", "telegram", "all"],
        default="feishu",
        help="push target, default: feishu",
    )
    parser.add_argument(
        "-m",
        "--markdown",
        action="store_true",
        help="send as markdown when target supports it",
    )
    # parser.add_argument("-i", "--img")
    args = parser.parse_args()
    
    if args.msgs == [] and sys.stdin.isatty():
        print("Error: At least one msg is required.")
        parser.print_usage()
        sys.exit(1)
    
    if args.msgs != []:
        text = "\n".join(args.msgs)

    if not sys.stdin.isatty():
        text = text + "\n\n" + "".join(sys.stdin.readlines())

    if text != "": 
        push(text, args.target, markdown=args.markdown)
