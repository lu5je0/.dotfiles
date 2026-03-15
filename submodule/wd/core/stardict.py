import json
import sqlite3

from paths import stardict_db_path


def stripword(word: str) -> str:
    return ''.join(ch for ch in word.lower() if ch.isalnum())


class StarDict(object):

    def __init__(self, filename, verbose=False):
        self.__dbname = filename
        if filename != ':memory:':
            os.path.abspath(filename)
        self.__conn = None
        self.__verbose = verbose
        self.__open()

    def __open(self):
        sql = '''
        CREATE TABLE IF NOT EXISTS "stardict" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL UNIQUE,
            "word" VARCHAR(64) COLLATE NOCASE NOT NULL UNIQUE,
            "sw" VARCHAR(64) COLLATE NOCASE NOT NULL,
            "phonetic" VARCHAR(64),
            "definition" TEXT,
            "translation" TEXT,
            "pos" VARCHAR(16),
            "collins" INTEGER DEFAULT(0),
            "oxford" INTEGER DEFAULT(0),
            "tag" VARCHAR(64),
            "bnc" INTEGER DEFAULT(NULL),
            "frq" INTEGER DEFAULT(NULL),
            "exchange" TEXT,
            "detail" TEXT,
            "audio" TEXT
        );
        CREATE INDEX IF NOT EXISTS "sd_1" ON stardict (word collate nocase);
        '''

        self.__conn = sqlite3.connect(self.__dbname, isolation_level='IMMEDIATE')
        self.__conn.isolation_level = 'IMMEDIATE'

        sql = '\n'.join([n.strip('\t') for n in sql.split('\n')]).strip('\n')
        self.__conn.executescript(sql)
        self.__conn.commit()

        fields = (
            'id', 'word', 'sw', 'phonetic', 'definition', 'translation',
            'pos', 'collins', 'oxford', 'tag', 'bnc', 'frq',
            'exchange', 'detail', 'audio'
        )
        self.__fields = tuple([(fields[i], i) for i in range(len(fields))])
        self.__names = {}
        for k, v in self.__fields:
            self.__names[k] = v
        self.__enable = self.__fields[3:]
        return True

    def __record2obj(self, record):
        if record is None:
            return None
        word = {}
        for k, v in self.__fields:
            word[k] = record[v]
        if word['detail']:
            text = word['detail']
            try:
                obj = json.loads(text)
            except Exception:
                obj = None
            word['detail'] = obj
        return word

    def close(self):
        if self.__conn:
            self.__conn.close()
        self.__conn = None

    def __del__(self):
        self.close()

    def out(self, text):
        if self.__verbose:
            print(text)
        return True

    def query(self, key):
        c = self.__conn.cursor()
        if isinstance(key, int):
            c.execute('select * from stardict where id = ?;', (key,))
        elif isinstance(key, str):
            c.execute('select * from stardict where word = ?', (key,))
        else:
            return None
        record = c.fetchone()
        return self.__record2obj(record)


class StarDictEngine(object):

    def __init__(self, db_path=None, verbose=False):
        if db_path is None:
            db_path = stardict_db_path()
        self.db_path = db_path
        self.verbose = verbose
        self.name = 'stardict'

    def is_available(self):
        return os.path.exists(self.db_path) and os.path.getsize(self.db_path) > 0

    def query(self, word):
        if not self.is_available():
            return None
        sd = StarDict(self.db_path, self.verbose)
        try:
            result = sd.query(word)
        finally:
            sd.close()
        if result:
            result['engine'] = self.name
        return result


def create_engine():
    return StarDictEngine()
