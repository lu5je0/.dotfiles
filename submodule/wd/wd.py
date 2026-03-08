#! /usr/bin/env python3

import argparse
import importlib.util
import os
import platform
import sys

import color_pattern


ENGINE_MODULES = [
    ('stardict_engine', 'stardict.py'),
    ('google_translator_engine', 'google-translator.py'),
]


def color(txt, pattern):
    return pattern.format(txt if txt else '')


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
    return ['stardict', 'google']


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
    print('英文释义：')
    print(color(result.get('definition', ''), color_pattern.PEP_PATTERN))
    print('变形：')
    print(color(result.get('exchange', ''), color_pattern.BROWN_PATTERN))


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
    parser.add_argument('--no-say', action='store_true', help='disable text-to-speech')
    return parser.parse_args()


def main():
    args = parse_args()

    if args.list_engines:
        for name in get_supported_engines():
            print(name)
        return 0

    word = args.word
    if not word and not sys.stdin.isatty():
        word = sys.stdin.read().strip()

    if not word:
        print('Please input a word!')
        return 1

    allowed_engines = args.engine if args.engine else get_supported_engines()
    engines = build_engines(allowed_engines)
    if not engines:
        print('无可用引擎')
        return 3

    result = query_with_engines(word, engines)

    if result is None:
        print('未找到该单词')
        return 2

    print_result(result, say_word=(not args.no_say))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
