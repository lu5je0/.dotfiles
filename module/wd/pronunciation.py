import re
import shutil
import subprocess
from html.parser import HTMLParser
from http.client import HTTPException
from time import monotonic
from urllib.error import HTTPError
from urllib.parse import quote, urljoin
from urllib.request import Request, urlopen


DICTIONARY_URL = 'https://en.wiktionary.org/w/rest.php/v1/page/'
COMMONS_AUDIO_URL = 'https://upload.wikimedia.org/wikipedia/commons/'
USER_AGENT = 'wd/1.0 (https://github.com/lu5je0/wd)'
MAX_AUDIO_BYTES = 2 * 1024 * 1024


class EnglishAudioParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_english = False
        self.in_audio = False
        self.urls = []

    def handle_starttag(self, tag, attrs):
        if tag == 'h2':
            self.in_english = dict(attrs).get('id') == 'English'
        elif self.in_english and tag == 'audio':
            self.in_audio = True
        elif self.in_audio and tag == 'source':
            src = dict(attrs).get('src')
            if src:
                url = urljoin(COMMONS_AUDIO_URL, src)
                if url.startswith(COMMONS_AUDIO_URL):
                    self.urls.append(url)

    def handle_endtag(self, tag):
        if tag == 'audio':
            self.in_audio = False


def is_american(url):
    filename = url.rsplit('/', 1)[-1].lower()
    return filename.startswith(('en-us-', 'en_us_'))


def dictionary_audio(word):
    query = quote(word.lower().replace('’', "'"), safe='')
    request = Request(
        DICTIONARY_URL + query + '/html',
        headers={'User-Agent': USER_AGENT},
    )
    parser = EnglishAudioParser()
    try:
        with urlopen(request, timeout=3) as response:
            parser.feed(response.read(2 * 1024 * 1024).decode('utf-8', errors='replace'))
    except (OSError, HTTPException, ValueError):
        return []
    return sorted(dict.fromkeys(parser.urls), key=is_american, reverse=True)


def download_audio(urls):
    deadline = monotonic() + 5
    for url in urls:
        remaining = deadline - monotonic()
        if remaining <= 0:
            break
        try:
            request = Request(url, headers={'User-Agent': USER_AGENT})
            with urlopen(request, timeout=min(remaining, 3)) as response:
                content_type = response.headers.get_content_type()
                if content_type.startswith('audio/') or content_type == 'application/ogg':
                    audio = response.read(MAX_AUDIO_BYTES + 1)
                    if 0 < len(audio) <= MAX_AUDIO_BYTES:
                        return audio
        except HTTPError as exc:
            if exc.code == 429:
                break
        except (OSError, HTTPException, ValueError):
            continue
    return None


def play_pronunciation(word):
    if not re.fullmatch(r"[A-Za-z]+(?:['’-][A-Za-z]+)*", word):
        return None
    player = shutil.which('mpv')
    if not player:
        return None
    audio = download_audio(dictionary_audio(word))
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
    return process.returncode
