import os


def _xdg_dir(env_name, default_suffix):
    value = os.environ.get(env_name)
    if value:
        return os.path.expanduser(value)
    return os.path.join(os.path.expanduser('~'), default_suffix)


def xdg_cache_home():
    return _xdg_dir('XDG_CACHE_HOME', '.cache')


def xdg_data_home():
    return _xdg_dir('XDG_DATA_HOME', '.local/share')


def xdg_state_home():
    return _xdg_dir('XDG_STATE_HOME', '.local/state')


def wd_cache_dir():
    return os.path.join(xdg_cache_home(), 'wd')


def wd_data_dir():
    return os.path.join(xdg_data_home(), 'wd')


def wd_state_dir():
    return os.path.join(xdg_state_home(), 'wd')


def history_dir():
    return wd_state_dir()


def history_file():
    return os.path.join(history_dir(), 'history.json')


def stardict_db_path():
    return os.path.join(wd_data_dir(), 'stardict', 'stardict.db')


def hanzi_detail_path():
    return os.path.join(wd_data_dir(), 'chinese-dictionary', 'char_detail.json')
