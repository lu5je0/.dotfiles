import json
import urllib.parse
import urllib.request


USER_AGENT = 'Mozilla/5.0 wd/1.0'


class GoogleTranslatorEngine(object):

    def __init__(self, timeout: int = 5):
        self.timeout = timeout
        self.name = 'google'

    def query(self, text: str):
        if not text:
            return None

        params = {
            'client': 'gtx',
            'sl': 'en',
            'tl': 'zh-CN',
            'dt': 't',
            'q': text,
        }
        url = 'https://translate.googleapis.com/translate_a/single?' + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})

        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                raw = resp.read().decode('utf-8')
            payload = json.loads(raw)
        except Exception:
            return None

        try:
            segments = payload[0] or []
            translated = ''.join(seg[0] for seg in segments if seg and seg[0])
            return {
                'word': text,
                'translation': translated,
                'definition': text,
                'phonetic': '',
                'exchange': '',
                'engine': self.name,
            }
        except Exception:
            return None


def create_engine():
    return GoogleTranslatorEngine()
