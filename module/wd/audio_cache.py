import sqlite3
from contextlib import closing, contextmanager
from pathlib import Path

from paths import wd_cache_dir


MAX_CACHE_ENTRIES = 256
MAX_CACHE_BYTES = 16 * 1024 * 1024


@contextmanager
def open_cache():
    directory = Path(wd_cache_dir())
    directory.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(directory / 'pronunciation.sqlite3', timeout=0.2)) as db, db:
        db.execute('''
            CREATE TABLE IF NOT EXISTS recordings (
                word TEXT PRIMARY KEY,
                audio BLOB NOT NULL,
                last_used INTEGER NOT NULL
            )
        ''')
        yield db


def load_audio(word):
    try:
        with open_cache() as db:
            db.execute('''
                UPDATE recordings
                SET last_used = (SELECT COALESCE(MAX(last_used), 0) + 1 FROM recordings)
                WHERE word = ?
            ''', (word,))
            row = db.execute('SELECT audio FROM recordings WHERE word = ?', (word,)).fetchone()
            return row[0] if row else None
    except (OSError, sqlite3.Error):
        return None


def store_audio(word, audio):
    if len(audio) > MAX_CACHE_BYTES:
        return
    try:
        with open_cache() as db:
            db.execute('''
                INSERT OR REPLACE INTO recordings (word, audio, last_used)
                VALUES (?, ?, (SELECT COALESCE(MAX(last_used), 0) + 1 FROM recordings))
            ''', (word, audio))
            size = 0
            for count, (last_used, audio_bytes) in enumerate(db.execute('''
                SELECT last_used, length(audio) FROM recordings ORDER BY last_used DESC
            '''), start=1):
                size += audio_bytes
                if count > MAX_CACHE_ENTRIES or size > MAX_CACHE_BYTES:
                    db.execute('DELETE FROM recordings WHERE last_used <= ?', (last_used,))
                    break
    except (OSError, sqlite3.Error):
        # Playback can succeed even when the cache is unavailable.
        pass
