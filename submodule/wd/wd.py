#! /usr/bin/env python3

import argparse
import importlib.util
import json
import os
import platform
import re
import sys
from datetime import datetime

import color_pattern
from init_dependencies import init_dependencies


ENGINE_MODULES = [
    ('chinese_dictionary_engine', 'chinese-dictionary.py'),
    ('stardict_engine', 'stardict.py'),
    ('google_translator_engine', 'google-translator.py'),
]
HISTORY_DIR = os.path.join(os.path.expanduser('~'), '.cache', 'wd')
HISTORY_FILE = os.path.join(HISTORY_DIR, 'history.json')
ANSI_RESET = '\033[0m'
ANSI_BOLD = '\033[1m'
ANSI_DIM = '\033[2m'
ANSI_GRAY = '\033[90m'
ANSI_CYAN = '\033[36m'
COUNT_WINDOW_SECONDS = 5 * 60


def color(txt, pattern):
    return pattern.format(txt if txt else '')


def style(text, *codes):
    return '{}{}{}'.format(''.join(codes), text, ANSI_RESET)


def get_say_cmd():
    s = platform.system()
    if s == 'Windows':
        return 'wsay'
    if s == 'Linux':
        return 'wsay -v 2'
    return 'say -v Alex'


def load_module(module_name, module_file):
    base_dir = os.path.dirname(__file__)
    engine_path = os.path.join(base_dir, 'core', module_file)
    if not os.path.exists(engine_path):
        return None

    spec = importlib.util.spec_from_file_location(module_name, engine_path)
    if spec is None or spec.loader is None:
        return None

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def get_supported_engines():
    return ['hanzi', 'stardict', 'google']


def build_engines(allowed_names=None):
    loaded_engines = {}
    for module_name, module_file in ENGINE_MODULES:
        module = load_module(module_name, module_file)
        if module is None or not hasattr(module, 'create_engine'):
            continue
        try:
            engine = module.create_engine()
        except Exception:
            continue
        engine_name = getattr(engine, 'name', '')
        if hasattr(engine, 'query') and engine_name:
            if hasattr(engine, 'is_available') and not engine.is_available():
                continue
            loaded_engines[engine_name] = engine

    if allowed_names is None:
        return [loaded_engines[name] for name in get_supported_engines() if name in loaded_engines]
    return [loaded_engines[name] for name in allowed_names if name in loaded_engines]


def query_with_engines(word, engines):
    for engine in engines:
        try:
            result = engine.query(word)
        except Exception:
            result = None
        if result:
            return result
    return None


def print_result(result, say_word=True):
    if say_word:
        os.popen(get_say_cmd() + ' {} 2>/dev/null'.format(result.get('word', '')))

    engine = result.get('engine', '')
    if engine:
        print('[{}]'.format(engine))

    print('[{}]'.format(color(result.get('phonetic', ''), color_pattern.BLUE_PATTERN)))
    print('中文释义：')
    print(color(result.get('translation', ''), color_pattern.GREEN_PATTERN))
    print('补充信息：' if engine == 'hanzi' else '英文释义：')
    print(color(result.get('definition', ''), color_pattern.PEP_PATTERN))
    print('变形：')
    print(color(result.get('exchange', ''), color_pattern.BROWN_PATTERN))


def load_history():
    if not os.path.exists(HISTORY_FILE):
        return {'records': []}
    try:
        with open(HISTORY_FILE, 'r', encoding='utf-8') as f:
            payload = json.load(f)
        records = payload.get('records', [])
        if isinstance(records, list):
            return {'records': records}
    except Exception:
        pass
    return {'records': []}


def save_history(payload):
    os.makedirs(HISTORY_DIR, exist_ok=True)
    with open(HISTORY_FILE, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def is_single_word(word):
    if not word:
        return False
    if re.search(r'\s', word):
        return False
    return re.fullmatch(r'[A-Za-z0-9]+', word)


def update_history(word):
    payload = load_history()
    records = payload.get('records', [])
    now_dt = datetime.now()
    now = now_dt.isoformat(timespec='seconds')
    matched = None
    for item in records:
        if item.get('word') == word:
            matched = item
            break
    if matched is None:
        matched = {'word': word, 'query_count': 1, 'last_query_time': now}
        records.append(matched)
        payload['records'] = records
        save_history(payload)
        return

    should_increment = True
    last_query_raw = matched.get('last_query_time')
    if last_query_raw:
        try:
            last_query_dt = datetime.fromisoformat(last_query_raw)
            if (now_dt - last_query_dt).total_seconds() < COUNT_WINDOW_SECONDS:
                should_increment = False
        except Exception:
            pass

    if should_increment:
        matched['query_count'] = int(matched.get('query_count', 0)) + 1
    matched['last_query_time'] = now
    payload['records'] = records
    save_history(payload)


def clear_stats():
    save_history({'records': []})
    print('历史记录已清空')
    return 0


def format_last_query_time(last_query_raw):
    if not last_query_raw:
        return ''
    try:
        dt = datetime.fromisoformat(last_query_raw)
        today = datetime.now().date()
        delta_days = (today - dt.date()).days
        if delta_days <= 0:
            ago = '0 day ago'
        elif delta_days == 1:
            ago = '1 day ago'
        else:
            ago = '{} days ago'.format(delta_days)
        return ago
    except Exception:
        return last_query_raw


def print_stats():
    payload = load_history()
    records = payload.get('records', [])
    if not records:
        print('暂无历史记录')
        return 0

    records = sorted(
        records,
        key=lambda x: (int(x.get('query_count', 0)), x.get('last_query_time', '')),
        reverse=True,
    )
    headers = ['word', 'count', 'last']
    rows = []
    for item in records:
        rows.append(
            [
                str(item.get('word', '')),
                str(int(item.get('query_count', 0))),
                format_last_query_time(item.get('last_query_time', '')),
            ]
        )

    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))

    header_line = '  '.join(style(headers[i].ljust(widths[i]), ANSI_BOLD, ANSI_CYAN) for i in range(len(headers)))
    sep_line = '  '.join(style('-' * widths[i], ANSI_DIM, ANSI_GRAY) for i in range(len(headers)))
    print(header_line)
    print(sep_line)
    for row in rows:
        styled = [
            style(row[0].ljust(widths[0]), ANSI_BOLD),
            style(row[1].rjust(widths[1]), ANSI_CYAN),
            style(row[2].ljust(widths[2]), ANSI_DIM, ANSI_GRAY),
        ]
        print('  '.join(styled))
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description='Word lookup: stardict first, then google.')
    parser.add_argument('word', nargs='?', help='word to query')
    parser.add_argument(
        '-e',
        '--engine',
        action='append',
        choices=get_supported_engines(),
        help='choose engine(s) in fallback order, can be used multiple times',
    )
    parser.add_argument('--list-engines', action='store_true', help='list available engines')
    parser.add_argument('--init', action='store_true', help='download local dictionary dependencies')
    parser.add_argument('--no-say', action='store_true', help='disable text-to-speech')
    parser.add_argument('--stats', action='store_true', help='show query history stats')
    parser.add_argument('--clear-stats', action='store_true', help='clear query history stats')
    parser.add_argument('--json', action='store_true', help='print result as JSON')
    return parser.parse_args()


def print_json(payload):
    print(json.dumps(payload, ensure_ascii=False))


def say_result(result):
    os.popen(get_say_cmd() + ' {} 2>/dev/null'.format(result.get('word', '')))


def main():
    args = parse_args()

    if args.list_engines:
        if args.json:
            print_json({'ok': True, 'engines': get_supported_engines()})
            return 0
        for name in get_supported_engines():
            print(name)
        return 0
    if args.clear_stats:
        if args.json:
            save_history({'records': []})
            print_json({'ok': True, 'cleared': True})
            return 0
        return clear_stats()
    if args.stats:
        if args.json:
            payload = load_history()
            print_json({'ok': True, 'records': payload.get('records', [])})
            return 0
        return print_stats()
    if args.init:
        try:
            results = init_dependencies()
        except Exception as exc:
            if args.json:
                print_json({'ok': False, 'error': str(exc), 'code': 4})
                return 4
            print(str(exc))
            return 4
        if args.json:
            print_json({'ok': True, 'initialized': results})
            return 0
        for item in results:
            status = 'downloaded' if item.get('downloaded') else 'skipped'
            print('{} [{}] -> {}'.format(item['engine'], status, item['path']))
        return 0

    word = args.word
    if not word and not sys.stdin.isatty():
        word = sys.stdin.read().strip()

    if not word:
        if args.json:
            print_json({'ok': False, 'error': 'Please input a word!', 'code': 1})
            return 1
        print('Please input a word!')
        return 1

    if is_single_word(word):
        try:
            update_history(word)
        except Exception:
            pass

    allowed_engines = args.engine if args.engine else get_supported_engines()
    engines = build_engines(allowed_engines)
    if not engines:
        if args.json:
            print_json({'ok': False, 'error': '无可用引擎', 'code': 3})
            return 3
        print('无可用引擎')
        return 3

    result = query_with_engines(word, engines)

    if result is None:
        if args.json:
            print_json({'ok': False, 'error': '未找到该单词', 'code': 2})
            return 2
        print('未找到该单词')
        return 2

    if not args.no_say:
        say_result(result)

    if args.json:
        print_json({'ok': True, 'result': result})
        return 0

    print_result(result, say_word=False)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
