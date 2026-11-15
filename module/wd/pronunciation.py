import re
import shutil
import subprocess
from http.client import HTTPException
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from audio_cache import load_audio, store_audio


YOUDAO_VOICE_URL = 'https://dict.youdao.com/dictvoice'
USER_AGENT = 'wd/1.0 (https://github.com/lu5je0/wd)'
MAX_AUDIO_BYTES = 2 * 1024 * 1024


def download_audio(word):
    # The dictionary's American English playback uses type=2.
    query = urlencode({'audio': word, 'type': 2})
    request = Request(
        f'{YOUDAO_VOICE_URL}?{query}',
        headers={'User-Agent': USER_AGENT},
    )
    try:
        with urlopen(request, timeout=3) as response:
            if response.headers.get_content_maintype() == 'audio':
                audio = response.read(MAX_AUDIO_BYTES + 1)
                if 0 < len(audio) <= MAX_AUDIO_BYTES:
                    return audio
    except (OSError, HTTPException, ValueError):
        return None
    return None


def play_pronunciation(word):
    if not re.fullmatch(r"[A-Za-z]+(?:['’-][A-Za-z]+)*", word):
        return None
    player = shutil.which('mpv')
    if not player:
        return None

    word = word.lower().replace('’', "'")
    cache_key = f'youdao-us:{word}'
    audio = load_audio(cache_key)
    cache_hit = audio is not None
    if not cache_hit:
        audio = download_audio(word)
    if audio is None:
        return None

    # A player can fail after producing sound, so only fall back if it couldn't start.
    try:
        process = subprocess.Popen(
            [
                player,
                '--no-config',
                '--no-video',
                '--no-terminal',
                # Feed silence while the output device wakes so the word starts intact.
                '--af=lavfi=[adelay=500:all=1]',
                '--',
                '-',
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return None
    with process:
        try:
            process.communicate(audio, timeout=8)
        except (OSError, subprocess.TimeoutExpired):
            process.kill()
            return 1
    if process.returncode == 0 and not cache_hit:
        store_audio(cache_key, audio)
    return process.returncode
