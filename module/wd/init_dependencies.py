import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request

from paths import hanzi_detail_path, stardict_db_path


USER_AGENT = 'Mozilla/5.0 wd/1.0'
STARDICT_URL = 'https://github.com/lu5je0/wd/releases/download/1.0/stardict.7z'
HANZI_DETAIL_URL = 'https://raw.githubusercontent.com/mapull/chinese-dictionary/refs/heads/main/character/char_detail.json'
STARDICT_DB_PATH = stardict_db_path()
HANZI_DETAIL_PATH = hanzi_detail_path()


def ensure_parent_dir(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)


def render_progress(label, downloaded, total):
    if total and total > 0:
        width = 28
        ratio = min(downloaded / total, 1.0)
        filled = int(width * ratio)
        bar = '=' * filled + ' ' * (width - filled)
        percent = int(ratio * 100)
        message = '\r{} [{}] {:>3}%'.format(label, bar, percent)
    else:
        size_mb = downloaded / (1024 * 1024)
        message = '\r{} {:.1f}MB'.format(label, size_mb)
    sys.stderr.write(message)
    sys.stderr.flush()


def download_file(url, dst_path, timeout=60):
    ensure_parent_dir(dst_path)
    req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        total = resp.headers.get('Content-Length')
        total = int(total) if total and total.isdigit() else 0
        downloaded = 0
        with open(dst_path, 'wb') as f:
            while True:
                chunk = resp.read(64 * 1024)
                if not chunk:
                    break
                f.write(chunk)
                downloaded += len(chunk)
                render_progress(os.path.basename(dst_path), downloaded, total)
    sys.stderr.write('\n')
    sys.stderr.flush()


def is_ready(path):
    return os.path.exists(path) and os.path.getsize(path) > 0


def init_hanzi_dependency():
    if is_ready(HANZI_DETAIL_PATH):
        return {'engine': 'hanzi', 'path': HANZI_DETAIL_PATH, 'downloaded': False}
    download_file(HANZI_DETAIL_URL, HANZI_DETAIL_PATH)
    return {'engine': 'hanzi', 'path': HANZI_DETAIL_PATH, 'downloaded': True}


def init_stardict_dependency():
    if is_ready(STARDICT_DB_PATH):
        return {'engine': 'stardict', 'path': STARDICT_DB_PATH, 'downloaded': False}
    if shutil.which('7za') is None:
        raise RuntimeError('7za not installed')

    with tempfile.TemporaryDirectory(prefix='wd-init-') as tmp_dir:
        archive_path = os.path.join(tmp_dir, 'stardict.7z')
        download_file(STARDICT_URL, archive_path)
        result = subprocess.run(
            ['7za', 'x', archive_path],
            cwd=tmp_dir,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or 'failed to extract stardict archive')
        extracted_db = os.path.join(tmp_dir, 'stardict.db')
        if not os.path.exists(extracted_db):
            raise RuntimeError('stardict.db not found in archive')
        ensure_parent_dir(STARDICT_DB_PATH)
        shutil.move(extracted_db, STARDICT_DB_PATH)

    return {'engine': 'stardict', 'path': STARDICT_DB_PATH, 'downloaded': True}


def init_dependencies():
    return [
        init_hanzi_dependency(),
        init_stardict_dependency(),
    ]
