import json
import os
import re


def is_single_hanzi(text: str) -> bool:
    return bool(text) and len(text) == 1 and re.match(r'^[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]$', text)


class ChineseDictionaryEngine(object):

    def __init__(self, cache_dir=None, timeout: int = 10):
        if cache_dir is None:
            cache_dir = os.path.join(os.path.expanduser('~'), '.cache', 'wd', 'chinese-dictionary')
        self.cache_dir = cache_dir
        self.name = 'hanzi'
        self.detail_path = os.path.join(self.cache_dir, 'char_detail.json')

    def is_available(self):
        return os.path.exists(self.detail_path) and os.path.getsize(self.detail_path) > 0

    def _find_record(self, path: str, char: str):
        needle = '"char" : "{}"'.format(char)
        try:
            with open(path, 'r', encoding='utf-8') as f:
                for line in f:
                    if needle not in line:
                        continue
                    line = line.strip()
                    if line.endswith(','):
                        line = line[:-1]
                    return json.loads(line)
        except Exception:
            return None
        return None

    def _format_translation(self, detail_record):
        if not detail_record:
            return ''

        parts = []
        seen_parts = set()
        for pronunciation in detail_record.get('pronunciations', []):
            explanation_texts = []
            for explanation in pronunciation.get('explanations', []):
                for text in self._collect_explanation_texts(explanation):
                    if text not in seen_parts:
                        explanation_texts.append(text)
                        seen_parts.add(text)
                if len(explanation_texts) >= 3:
                    break
            if not explanation_texts:
                continue
            parts.append('；'.join(explanation_texts))
            if len(parts) >= 3:
                break
        return '\n'.join(parts)

    def _collect_explanation_texts(self, explanation):
        texts = []

        content = (explanation.get('content') or '').strip()
        if content:
            texts.append(content)

        texts.extend(self._format_explanation_fallback(explanation))
        return texts

    def _format_explanation_fallback(self, explanation):
        fallback_texts = []

        simplified = (explanation.get('simplified') or '').strip()
        if simplified:
            fallback_texts.append('简体: {}'.format(simplified))

        variant = (explanation.get('variant') or '').strip()
        if variant:
            fallback_texts.append('异体: {}'.format(variant))

        traditional = self._normalize_text_list(explanation.get('traditional'))
        if traditional:
            fallback_texts.append('繁体: {}'.format(traditional))

        modern = self._normalize_text_list(explanation.get('modern'))
        if modern:
            fallback_texts.append('今字: {}'.format(modern))

        same = (explanation.get('same') or '').strip()
        if same:
            fallback_texts.append('同“{}”'.format(same))

        return fallback_texts

    def _normalize_text_list(self, value):
        if isinstance(value, list):
            return '、'.join(item.strip() for item in value if isinstance(item, str) and item.strip())
        return (value or '').strip()

    def _format_definition(self, detail_record):
        meta = []
        words = []
        if detail_record:
            for pronunciation in detail_record.get('pronunciations', []):
                for explanation in pronunciation.get('explanations', []):
                    for word in explanation.get('words', []):
                        text = (word.get('word') or '').strip()
                        if text:
                            words.append(text)
                        if len(words) >= 6:
                            break
                    if len(words) >= 6:
                        break
                if len(words) >= 6:
                    break
        if words:
            meta.append('组词: {}'.format('、'.join(words)))

        return '\n'.join(meta)

    def query(self, word: str):
        if not is_single_hanzi(word):
            return None

        if not self.is_available():
            return None

        detail_record = self._find_record(self.detail_path, word)
        if not detail_record:
            return None

        pinyin_list = []
        for pronunciation in detail_record.get('pronunciations', []):
            pinyin = pronunciation.get('pinyin')
            if pinyin:
                pinyin_list.append(pinyin)

        translation = self._format_translation(detail_record)
        definition = self._format_definition(detail_record)

        return {
            'word': word,
            'translation': translation,
            'definition': definition,
            'phonetic': ' / '.join(dict.fromkeys(pinyin_list)),
            'exchange': '',
            'engine': self.name,
        }


def create_engine():
    return ChineseDictionaryEngine()
