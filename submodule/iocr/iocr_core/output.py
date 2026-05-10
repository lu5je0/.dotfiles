import os
import shlex
import subprocess


def print_text(text: str) -> None:
    print(text, end="" if text.endswith("\n") else "\n")


def open_in_editor(png_bytes: bytes, text: str, editor: str = "nvim") -> None:
    tmp_dir = "/tmp/iocr"
    os.makedirs(tmp_dir, exist_ok=True)
    img_path = os.path.join(tmp_dir, "source.png")
    md_path = os.path.join(tmp_dir, "ocr.md")

    with open(img_path, "wb") as f:
        f.write(png_bytes)

    content = f"![ocr]({img_path})\n\n---\n\n{text}\n"
    with open(md_path, "w") as f:
        f.write(content)

    subprocess.run([*shlex.split(editor), md_path])
