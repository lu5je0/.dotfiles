## wd

Word translator CLI.

Default behavior:
- Query `hanzi` first for a single Chinese character, only after `wd --init`.
- Query `stardict` first (offline), only after `wd --init`.
- Fallback to `google` translator (online).

## Usage

```bash
wd hello
wd --say-only hello
wd --no-say hello
wd --json --no-say hello
wd -e stardict -e google hello
wd --list-engines
wd --init
wd --stats
wd --delete-stat hello
wd --clear-stats
echo "good for you" | wd
```

## Arguments

- `word`: word or phrase to query
- `-e, --engine`: choose engine(s) in fallback order, supports:
  - `hanzi`
  - `stardict`
  - `google`
- `--list-engines`: print available engines
- `--init`: download local dictionary dependencies for `hanzi` and `stardict`
- `--no-say`: disable text-to-speech
- `--say-only`: speak the text without looking it up
- `--stats`: show query history stats
- `--delete-stat WORD`: delete stats for a single word
- `--clear-stats`: clear all query history stats
- `--json`: print machine-readable JSON

Successful lookups are spoken by default. With `mpv` installed, `wd` requests
recordings for individual English words through the
[Wiktionary REST API](https://en.wiktionary.org/wiki/Special:RestSandbox).
It downloads one recording per lookup, preferring American English. Playback
starts with 500 ms of silence to give idle audio devices time to wake. Phrases
and words without downloadable recordings use local speech. On Linux, `wd` uses
`wsay` if available and otherwise uses `spd-say`. Windows uses `wsay`, and macOS
uses `say -v Alex`. Use `--no-say` to skip pronunciation requests and playback.

`--json` success example:

```json
{"ok": true, "result": {"word": "hello", "translation": "你好", "definition": "...", "phonetic": "həˈləʊ", "exchange": "", "engine": "stardict"}}
```

`wd --init` downloads the local dictionary dependencies into `XDG_DATA_HOME/wd` (default: `~/.local/share/wd`):

- `https://raw.githubusercontent.com/mapull/chinese-dictionary/refs/heads/main/character/char_detail.json`
- `https://github.com/lu5je0/wd/releases/download/1.0/stardict.7z`

## History

History is persisted in JSON:

- path: `XDG_STATE_HOME/wd/history.json` (default: `~/.local/state/wd/history.json`)
- tracked fields:
  - `word`
  - `query_count`
  - `last_query_time`

Dictionary data is stored separately from cache:

- `~/.local/share/wd/stardict/stardict.db`
- `~/.local/share/wd/chinese-dictionary/char_detail.json`

Only single-word queries are recorded. Phrases like `good for you` are ignored.

`wd --stats` output:
- `word` column first
- `last_query_time` column last
- aligned columns
- relative time format like `2 days ago (Mar 06)`

## Engine Interface

All engines use the same interface for easy extension:

- module function: `create_engine()`
- engine method: `query(word) -> dict | None`
- engine name: `engine.name`

`query` should return a dict with keys like:
- `word`
- `translation`
- `definition`
- `phonetic`
- `exchange`
- `engine`

To add a new engine:
1. Add a new file under `core/`.
2. Implement `create_engine()` and `query(word)`.
3. Register it in `wd.py` `ENGINE_MODULES`.
