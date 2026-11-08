"""Read dotfiles settings with JSON comments and trailing commas."""

import json
import re


_STRING = r'"(?:[^"\\]|\\.)*"'
_COMMENTS = re.compile(_STRING + r"|//[^\r\n]*|/\*[\s\S]*?\*/")
_TRAILING_COMMAS = re.compile(_STRING + r"|,\s*(?=[}\]])")


def load(file):
    text = _COMMENTS.sub(
        lambda match: re.sub(r"[^\r\n]", " ", match[0])
        if match[0].startswith("/") else match[0],
        file.read(),
    )
    text = _TRAILING_COMMAS.sub(
        lambda match: match[0] if match[0].startswith('"') else match[0][1:],
        text,
    )
    return json.loads(text)
