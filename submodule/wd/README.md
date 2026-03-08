## wd

Word translator CLI.

Default behavior:
- Query `stardict` first (offline).
- Fallback to `google` translator (online).

## Usage

```bash
wd hello
wd --no-say hello
wd -e stardict -e google hello
wd --list-engines
echo "good for you" | wd
```

## Arguments

- `word`: word or phrase to query
- `-e, --engine`: choose engine(s) in fallback order, supports:
  - `stardict`
  - `google`
- `--list-engines`: print available engines
- `--no-say`: disable text-to-speech

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
