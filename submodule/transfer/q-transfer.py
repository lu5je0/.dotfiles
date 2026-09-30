#!/usr/bin/env python3
"""
q-transfer - 文件上传客户端

使用浏览器授权流程:
1. 运行 q-transfer -r <host> 注册设备
2. 按提示打开浏览器授权
3. 授权后即可上传文件
"""

import argparse
import json
import mimetypes
import os
import platform
import re
import subprocess
import sys
import tempfile
import time
import uuid
import zlib
import requests
from tqdm import tqdm
from tqdm.utils import CallbackIOWrapper


class TokenHolder:
    """管理客户端授权 token，按服务器地址存储"""

    STATE_BASE_DIR = os.path.expanduser("~/.local/state/transfer")

    def __init__(self, host):
        # 从 host 生成一个安全的目录名
        self.host = host.rstrip('/')
        self.host_id = self._get_host_id(self.host)
        self.token = ""
        self.client_id = ""

    def _get_host_id(self, host):
        """从 host URL 生成目录名"""
        # 去掉协议前缀，替换特殊字符
        host = host.replace('https://', '').replace('http://', '')
        host = host.replace('/', '_').replace(':', '_')
        return host

    def get_state_dir(self):
        """获取状态目录 ~/.local/state/transfer/<host_id>/"""
        state_path = os.path.join(self.STATE_BASE_DIR, self.host_id)
        if not os.path.exists(state_path):
            os.makedirs(state_path, exist_ok=True)
        return state_path

    def get_token_file(self):
        return os.path.join(self.get_state_dir(), 'token')

    def get_client_id_file(self):
        return os.path.join(self.get_state_dir(), 'client_id')

    @classmethod
    def get_last_server_file(cls):
        """获取最后使用的服务器记录文件"""
        return os.path.join(cls.STATE_BASE_DIR, 'last_server')

    @classmethod
    def save_last_server(cls, host):
        """保存最后使用的服务器"""
        if not os.path.exists(cls.STATE_BASE_DIR):
            os.makedirs(cls.STATE_BASE_DIR, exist_ok=True)
        with open(cls.get_last_server_file(), 'w') as f:
            f.write(host.rstrip('/'))

    @classmethod
    def load_last_server(cls):
        """加载最后使用的服务器"""
        file_path = cls.get_last_server_file()
        if os.path.exists(file_path):
            with open(file_path, 'r') as f:
                return f.read().strip()
        return None

    def load(self):
        """加载保存的 token 和 client_id"""
        token_file = self.get_token_file()
        client_id_file = self.get_client_id_file()

        if os.path.exists(token_file):
            with open(token_file, 'r') as f:
                self.token = f.read().strip()

        if os.path.exists(client_id_file):
            with open(client_id_file, 'r') as f:
                self.client_id = f.read().strip()

        return bool(self.token and self.client_id)

    def save(self):
        """保存 token 和 client_id"""
        with open(self.get_token_file(), 'w') as f:
            f.write(self.token)
        with open(self.get_client_id_file(), 'w') as f:
            f.write(self.client_id)

    def clear(self):
        """清除保存的凭证"""
        self.token = ""
        self.client_id = ""
        token_file = self.get_token_file()
        client_id_file = self.get_client_id_file()
        if os.path.exists(token_file):
            os.remove(token_file)
        if os.path.exists(client_id_file):
            os.remove(client_id_file)


class AuthManager:
    """处理浏览器授权流程"""

    def __init__(self, host):
        self.host = host.rstrip('/')
        self.token_holder = TokenHolder(self.host)

    def is_authorized(self):
        """检查是否已授权"""
        return self.token_holder.load()

    def register(self):
        """注册新设备并等待授权"""
        print(f"正在注册设备到 {self.host}...")

        try:
            resp = requests.post(
                f"{self.host}/api/auth/register",
                json={"hostname": platform.node()}
            )
            resp.raise_for_status()
        except requests.RequestException as e:
            print(f"注册失败: {e}")
            sys.exit(1)

        # 获取 client_id
        self.token_holder.client_id = resp.headers.get('X-Client-Id', '')
        if not self.token_holder.client_id:
            print("注册失败: 未获取到 client_id")
            sys.exit(1)

        # 解析授权 URL
        text = resp.text
        auth_url = None
        for line in text.split('\n'):
            if line.startswith('http'):
                auth_url = line.strip()
                break

        if not auth_url:
            print("注册失败: 未获取到授权链接")
            sys.exit(1)

        print(f"\n请打开浏览器访问以下链接授权:")
        print(f"  {auth_url}")

        # 轮询等待授权
        print("\n等待授权中", end="")
        sys.stdout.flush()

        max_wait = 300  # 最多等待5分钟
        for i in range(max_wait):
            time.sleep(1)
            print(".", end="")
            sys.stdout.flush()

            try:
                check_resp = requests.get(
                    f"{self.host}/api/auth/check/{self.token_holder.client_id}"
                )
                if check_resp.status_code == 200:
                    data = check_resp.json()
                    if data.get('status') == 'approved':
                        self.token_holder.token = data.get('token', '')
                        self.token_holder.save()
                        TokenHolder.save_last_server(self.host)
                        print("\n\n授权成功!")
                        print(f"凭证保存在: {self.token_holder.get_state_dir()}")
                        return True
                    elif data.get('status') == 'rejected':
                        print("\n\n授权被拒绝")
                        return False
            except requests.RequestException:
                pass

        print("\n\n授权超时，请重试")
        return False

    def ensure_authorized(self):
        """确保已授权，如未授权则引导用户完成授权流程"""
        if self.is_authorized():
            return True

        print(f"未授权，请先运行: q-transfer -r {self.host}")
        return False


def parse_expire_spec(text):
    """'7d' / '24h' / '30m' / 'never' -> 发给服务端的字符串（epoch 秒 或 'never'）"""
    if text is None:
        return None
    t = text.strip().lower()
    if t in ('never', 'none', '0'):
        return 'never'
    m = re.fullmatch(r'(\d+)\s*([dhm])', t)
    if not m:
        raise ValueError(f"无法解析 --expire {text!r}：支持 7d / 24h / 30m / never")
    n, unit = int(m.group(1)), m.group(2)
    return str(int(time.time()) + n * {'d': 86400, 'h': 3600, 'm': 60}[unit])


def fmt_expires(ts):
    if ts is None:
        return '永不过期'
    left = int(ts) - int(time.time())
    if left <= 0:
        return '已过期'
    if left >= 86400:
        return f'{left // 86400} 天后'
    return f'{left // 3600} 小时后'


class Remote:
    """CLI 的读/管理侧：列包、看详情、删包、改过期。

    走同一个 Bearer token —— 服务端把它解析成 client_id，只返回**这台设备
    自己上传的**包（以及加 upload_client_id 之前上传、无法归因的历史包）。
    以前这些事只能开浏览器做，等于把 CLI 用户挡在门外。
    """

    def __init__(self, host):
        self.host = host
        self.auth = AuthManager(host)

    def _ready(self):
        return self.auth.ensure_authorized()

    def _headers(self):
        return {'Authorization': f'Bearer {self.auth.token_holder.token}'}

    def _request(self, method, path, **kw):
        kw.setdefault('headers', self._headers())
        kw.setdefault('timeout', 60)
        r = requests.request(method, f'{self.host}{path}', **kw)
        if r.status_code == 401:
            print(f'未授权，请先运行: q-transfer -r {self.host}')
            return None
        if r.status_code == 403:
            print(f'没有权限：{r.json().get("detail", r.text[:120])}')
            return None
        r.raise_for_status()
        return r

    def list_bundles(self, per_page=50):
        r = self._request('GET', '/api/bundles', params={'per_page': per_page})
        if r is None:
            return None
        data = r.json()
        items = data.get('items', [])
        print(f'共 {data.get("total", len(items))} 个包'
              + (f'（显示前 {len(items)} 个）' if data.get('total', 0) > len(items) else ''))
        print()
        print(f'{"ID":<34}{"名字/入口":<28}{"文件":>4}{"大小":>10}{"下载":>6}  过期')
        for b in items:
            label = b.get("name") or b["entry_path"] or '(无入口)'
            print(f'{b["id"]:<34}{label[:26]:<28}'
                  f'{b["file_count"]:>4}{FileHelper.convert_bytes(b["size"]):>10}'
                  f'{b.get("download_count") or 0:>6}  {fmt_expires(b.get("expires_at"))}')
        if items:
            print()
            print(f'更新某个包： q-transfer <目录> -u {items[0]["id"]}')
            print(f'看详情：     q-transfer --info {items[0]["id"]}')
        return items

    def info(self, bundle_id):
        """看一个包的详情。

        走 GET /api/bundles/{id} —— 包的规范接口。以前借的是公开的
        /api/files/{id}（一个 files 接口返回 file 里塞 bundle），
        那个不返回包名。
        """
        r = self._request('GET', f'/api/bundles/{bundle_id}')
        if r is None:
            return None
        d = r.json()
        entry = d.get('entry_path') or ''
        host = self.host

        print(f'包名:     {d["name"] or "（未命名）"}')
        print(f'入口:     {entry or "（无入口，分享用下面的索引地址）"}')
        print(f'大小:     {FileHelper.convert_bytes(d.get("size") or 0)}')
        print(f'文件数:   {d.get("file_count") or 1}')
        print(f'过期:     {fmt_expires(d.get("expires_at"))}')
        if d.get('download_count'):
            print(f'下载:     {d["download_count"]} 次 / {d.get("unique_ips") or 0} 个 IP')
        print()
        print(f'分享:     {host}/v/{bundle_id}/{entry}' if entry
              else f'索引:     {host}/v/{bundle_id}/')
        print(f'预览:     {host}/v/{bundle_id}')
        print(f'整包下载: {host}/b/{bundle_id}.tar')

        files = d.get('files') or []
        if len(files) > 1:
            print()
            print('包内文件:')
            for m in files:
                mark = '  ← 入口' if m.get('is_entry') else ''
                print(f'  {FileHelper.convert_bytes(m.get("size") or 0):>10}  {m["rel_path"]}{mark}')
                print(f'{"":>12}下载 {host}/d/{bundle_id}/{m["rel_path"]}')
        return d

    def delete_bundle(self, bundle_id, assume_yes=False):
        r = self._request('GET', f'/api/files/{bundle_id}')
        name = ''
        if r is not None:
            b = (r.json().get('bundle') or {})
            name = b.get('entry_path') or ''
        if not assume_yes:
            try:
                if input(f'删除整包 {bundle_id}（{name}）及其所有文件？[y/N] ').strip().lower() not in ('y', 'yes'):
                    print('已取消')
                    return False
            except (KeyboardInterrupt, EOFError):
                # 无 tty（管道/CI）时 input() 会抛 EOFError —— 当作取消，
                # 不能让它冒成 traceback，更不能默认「是」
                print()
                return False
        r = self._request('DELETE', f'/api/bundles/{bundle_id}')
        if r is None:
            return False
        print(f'已删除 {bundle_id}')
        return True

    def set_expires(self, bundle_id, spec):
        body = {'expires_at': None if spec == 'never' else int(spec)}
        r = self._request('PUT', f'/api/bundles/{bundle_id}/expires', json=body)
        if r is None:
            return False
        print(f'过期时间已设为：{fmt_expires(body["expires_at"])}')
        return True


class BundleMap:
    """记住「本地目录 -> 远端 bundle_id」，让原地更新不用手打 id。

    存 ~/.local/state/transfer/bundles.json，**按 host 分组**（多服务器不串）。

    key 用第一个参数的绝对路径 —— 这正是用户心里认定的「这个项目」。
    目录改名/移动会让映射失效，那种情况下退回显式 `-u <id>` 即可：
    宁可找不到，也不能猜错到别的包上（误更新比找不到严重得多）。
    """

    PATH = os.path.join(TokenHolder.STATE_BASE_DIR, 'bundles.json')

    @classmethod
    def _load(cls):
        try:
            with open(cls.PATH, encoding='utf-8') as f:
                data = json.load(f)
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    @classmethod
    def _save(cls, data):
        os.makedirs(os.path.dirname(cls.PATH), exist_ok=True)
        tmp = cls.PATH + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        os.replace(tmp, cls.PATH)      # 原子替换，别写坏已有记录

    @staticmethod
    def key_for(paths):
        return os.path.abspath(paths[0]) if paths else ''

    @classmethod
    def remember(cls, host, paths, bundle_id, entry=None):
        if not bundle_id or not paths:
            return
        data = cls._load()
        data.setdefault(host.rstrip('/'), {})[cls.key_for(paths)] = {
            'bundle_id': bundle_id,
            'entry': entry,
            'updated_at': int(time.time()),
        }
        cls._save(data)

    @classmethod
    def recall(cls, host, paths):
        entry = (cls._load().get(host.rstrip('/')) or {}).get(cls.key_for(paths))
        return entry if isinstance(entry, dict) else None


class FileHelper:
    @staticmethod
    def extract_id(url):
        """从 {host}/v/{id}[/...] 、/d/{id}/... 、/b/{id}.tar 里取出 id"""
        for marker in ('/v/', '/d/', '/b/'):
            if marker in url:
                rest = url.split(marker, 1)[1]
                return rest.split('/')[0].split('.')[0]
        return ''

    @staticmethod
    def is_render_url(url):
        """是 /v/{id}/{rel_path}（渲染直链）还是 /v/{id}（预览页）？

        不能再用 '/r/' in url 判断 —— /r/ 路由已经并入 /v/，那样永远为假。
        靠 /v/ 之后还有没有路径段来区分。
        """
        if '/v/' not in url:
            return False
        return '/' in url.split('/v/', 1)[1]

    @staticmethod
    def print_share_hints(base_url, bundle_id, paths=None, entry=None):
        """打印 bundle_id / 下次更新命令 / 整包下载链接。

        这三行值得单独打，是因为 CLI 的主要用法就是原地更新，而 -u 需要
        bundle_id —— 不打出来就只能翻 scrollback 或开浏览器去列表页复制，
        等于把「链接永久有效」这个核心能力的使用路径切断了。
        """
        if not bundle_id:
            return
        print(f'Bundle ID:     {bundle_id}')
        if paths:
            cmd = 'q-transfer ' + ' '.join(paths)
            if entry:
                cmd += f' --entry {entry}'
            print(f'下次更新:       {cmd} -u {bundle_id}')
        host = base_url.split('/v/', 1)[0] if '/v/' in base_url else ''
        if host:
            print(f'整包下载:       {host}/b/{bundle_id}.tar')

    @staticmethod
    def convert_bytes(num):
        for x in ['B', 'KB', 'MB', 'GB', 'TB']:
            if num < 1024.0:
                return ('%.2f' % num).rstrip('0').rstrip('.') + x
            num /= 1024.0

    @staticmethod
    def file_size(file_path):
        if os.path.isfile(file_path):
            file_info = os.stat(file_path)
            return FileHelper.convert_bytes(file_info.st_size)


class TransferConfig:
    GZIP_CHUNK_SIZE = 1024 * 1024
    GZIP_PROGRESS_UPDATE_INTERVAL = 0.2
    GZIP_SKIP_EXTENSIONS = {
        '.exe', '.7z', '.avi', '.br', '.bz2', '.cab', '.gz', '.heic', '.jpeg', '.jpg',
        '.m4a', '.m4v', '.mkv', '.mov', '.mp3', '.mp4', '.ogg', '.ogv', '.opus',
        '.pdf', '.png', '.rar', '.tar', '.tgz', '.webm', '.webp', '.xz', '.zip',
    }


class GzipStream:
    """Stream gzip-compressed bytes while tracking upload progress."""

    def __init__(self, path, progress_bar, level=1, chunk_size=TransferConfig.GZIP_CHUNK_SIZE):
        self.path = path
        self.progress_bar = progress_bar
        self.chunk_size = chunk_size
        self.compressor = zlib.compressobj(level=level, wbits=16 + zlib.MAX_WBITS)
        self.file = open(path, 'rb')
        self.total_input = 0
        self.total_compressed = 0
        self._pending = b''
        self._eof = False
        self._last_postfix_update = 0.0

    def _update_progress(self, input_size, compressed_size):
        if input_size:
            self.total_input += input_size
            self.progress_bar.update(input_size)
        self.total_compressed += compressed_size

        now = time.monotonic()
        if (
            self.total_input > 0 and
            now - self._last_postfix_update >= TransferConfig.GZIP_PROGRESS_UPDATE_INTERVAL
        ):
            ratio = (1 - self.total_compressed / self.total_input) * 100
            self.progress_bar.set_postfix_str(f"saved={ratio:.1f}%")
            self._last_postfix_update = now

    def read(self, size=-1):
        if self._pending:
            chunk = self._pending
            self._pending = b''
            return chunk

        while not self._eof:
            raw = self.file.read(self.chunk_size)
            if raw:
                compressed = self.compressor.compress(raw)
                self._update_progress(len(raw), len(compressed))
                if compressed:
                    return compressed
                continue

            tail = self.compressor.flush()
            self._eof = True
            self.file.close()
            if self.total_input > 0:
                ratio = (1 - (self.total_compressed + len(tail)) / self.total_input) * 100
                self.progress_bar.set_postfix_str(f"saved={ratio:.1f}%")
            if tail:
                self.total_compressed += len(tail)
                return tail

        return b''

    def __iter__(self):
        return self

    def __next__(self):
        chunk = self.read()
        if not chunk:
            raise StopIteration
        return chunk


class Uploader:
    def __init__(self, host):
        self.host = host.rstrip('/')
        self.auth = AuthManager(self.host)

    @staticmethod
    def print_qr_code_ascii(url):
        import qrcode
        qr = qrcode.QRCode(version=2, box_size=10, border=2)
        qr.add_data(url)
        qr.make(fit=True)
        qr.print_ascii()

    @staticmethod
    def should_skip_gzip(file_path):
        return os.path.splitext(file_path)[1].lower() in TransferConfig.GZIP_SKIP_EXTENSIONS

    # 目录里默认跳过的目录/文件
    BUNDLE_SKIP_DIRS = {'.git', 'node_modules', '__pycache__', '.venv', 'dist', '.idea'}
    BUNDLE_SKIP_FILES = {'.DS_Store', 'Thumbs.db'}

    @staticmethod
    def collect_bundle_items(paths):
        """把路径展开成 [(绝对路径, 包内相对路径)]。传目录会保留目录结构。"""
        items = []
        for p in paths:
            if os.path.isdir(p):
                base = os.path.abspath(p)   # 目录内容落在包根，入口才是 index.html
                for root, dirs, fs in os.walk(p):
                    dirs[:] = sorted(d for d in dirs if d not in Uploader.BUNDLE_SKIP_DIRS)
                    for f in sorted(fs):
                        if f in Uploader.BUNDLE_SKIP_FILES:
                            continue
                        ap = os.path.join(root, f)
                        items.append((ap, os.path.relpath(ap, base).replace(os.sep, '/')))
            else:
                items.append((p, os.path.basename(p)))
        return items

    def upload_bundle(self, paths, entry=None, qrcode=True, bundle_id=None,
                      expires_at=None, name=None):
        """打包上传：一个「文件夹」= 一条记录（一个 bundle_id）。

        传 bundle_id 时走原地更新（PUT），**id 不变 => 分享链接不变**。
        资源引用请用相对路径（src="img/a.png"），不要用 src="/img/a.png"。
        """
        if not self.auth.ensure_authorized():
            return False

        items = self.collect_bundle_items(paths)
        if not items:
            print("没有可上传的文件")
            return False

        names = [rel for _, rel in items]

        # 不再猜入口。以前 index.html 有特权（会静默盖过别的页面），
        # 猜不出来时还会直接拒绝上传（纯图片目录就传不了）。
        # 现在：只有 --entry 显式给了才设；否则这个包「没有门面」，
        # /v/{bundle_id}/ 会出一个目录索引，事后也能在网页上补设。
        entry_explicit = entry is not None
        if entry_explicit and entry.strip().lower() in ('none', '-', '/'):
            entry = ''                      # 显式表示不要入口
        elif entry_explicit:
            entry = entry.strip().lstrip('/')
        else:
            # None = **完全不传这个字段**。服务端据此区分：
            #   新建 -> 没有入口；原地更新 -> 保持原有入口不动
            # 传 '' 才是「明确清掉入口」。搞混的话 -u 会把入口误删。
            entry = None

        if entry and entry not in names:
            print(f"入口文件不在这次上传的列表里：{entry}")
            print(f"候选：{', '.join(names[:8])}")
            print("（想明说「不要入口」用 --entry none）")
            return False

        total = sum(os.path.getsize(ap) for ap, _ in items)
        action = f"原地更新 {bundle_id}" if bundle_id else "打包上传"
        print(f"{action}：{len(items)} 个文件 / {FileHelper.convert_bytes(total)} -> {self.host}")
        for _, rel in items:
            print(f"  {rel}")

        # 只把用户真正给过的字段发出去（见上面 entry 的说明）
        _payload = {}
        if entry is not None:
            _payload['entry'] = entry
        if expires_at is not None:
            _payload['expires_at'] = expires_at
        if name:
            _payload['name'] = name

        opened, files = [], []
        try:
            for ap, rel in items:
                fh = open(ap, 'rb')
                opened.append(fh)
                files.append(('files', (rel, fh)))
            url = (f"{self.host}/api/bundles/{bundle_id}" if bundle_id
                   else f"{self.host}/api/bundles")
            resp = requests.request(
                'PUT' if bundle_id else 'POST', url,
                headers={'Authorization': f'Bearer {self.auth.token_holder.token}'},
                data=_payload,
                files=files,
                timeout=600,
            )
            resp.raise_for_status()
        except requests.RequestException as e:
            body = getattr(getattr(e, 'response', None), 'text', '')
            print(f"\n上传失败: {e}\n{body[:300]}")
            return False
        finally:
            for fh in opened:
                fh.close()

        lines = [ln.strip() for ln in (resp.text or '').splitlines() if ln.strip()]
        render_url = lines[0] if lines else ''
        view_url = lines[1] if len(lines) > 1 else ''
        # 服务端返回第一行是 /v/{id}/{entry} 或 /v/{id}/（无入口）。
        # 用**服务端解析后**的值，-u 没传 entry 时也能显示真实入口。
        _tail = render_url.split('/v/', 1)[-1].split('/', 1)
        resolved_entry = _tail[1] if len(_tail) > 1 else ''
        if resolved_entry:
            print(f"\nRender link:   {render_url}")
            print('               (sandboxed HTML page — safe to share)')
        else:
            print(f"\nIndex link:    {render_url}")
            print('               (目录索引页 — 无入口的包用这个分享，不依赖 JS)')
        if view_url:
            print(f'Preview link:  {view_url}')

        # 原地更新要用 bundle_id，这里顺手打出来并记进 BundleMap
        bid = bundle_id or FileHelper.extract_id(render_url)
        FileHelper.print_share_hints(render_url, bid, paths=paths, entry=resolved_entry)
        BundleMap.remember(self.host, paths, bid, resolved_entry)

        if not resolved_entry:
            print('               这个包没有入口；要指定就加 --entry <路径>，')
            print(f'               或事后在网页上设：{self.host}/v/{bid}')

        if qrcode and render_url:
            print()
            self.print_qr_code_ascii(render_url)
        return True

    def upload(self, file_path, qrcode=True, use_gzip=True, gzip_level=1, filename=None):
        """上传单个文件"""
        # 确保已授权
        if not self.auth.ensure_authorized():
            return False

        filename = filename or os.path.basename(file_path)
        file_size = os.stat(file_path).st_size

        headers = {
            'Authorization': f'Bearer {self.auth.token_holder.token}'
        }

        effective_gzip = use_gzip
        if effective_gzip and self.should_skip_gzip(file_path):
            print("gzip: skipped for already-compressed file type")
            effective_gzip = False

        if effective_gzip:
            headers['Content-Encoding'] = 'gzip'

            with tqdm(total=file_size, unit="B", unit_scale=True, unit_divisor=1024, desc="uploading") as t:
                stream = GzipStream(file_path, t, level=gzip_level)
                try:
                    resp = requests.put(
                        f"{self.host}/{filename}",
                        data=stream,
                        headers=headers
                    )
                    resp.raise_for_status()
                except requests.RequestException as e:
                    print(f"\n上传失败: {e}")
                    return False
                compressed_size = stream.total_compressed

            if file_size > 0:
                ratio = (1 - compressed_size / file_size) * 100
                print(f"gzip: {FileHelper.convert_bytes(file_size)} -> {FileHelper.convert_bytes(compressed_size)} ({ratio:.1f}% saved)")
        else:
            with open(file_path, "rb") as f:
                with tqdm(total=file_size, unit="B", unit_scale=True, unit_divisor=1024) as t:
                    wrapped_file = CallbackIOWrapper(t.update, f, "read")
                    try:
                        resp = requests.put(
                            f"{self.host}/{filename}",
                            data=wrapped_file,
                            headers=headers
                        )
                        resp.raise_for_status()
                    except requests.RequestException as e:
                        print(f"\n上传失败: {e}")
                        return False

        # 输出结果
        # 服务端返回两行：下载链接 + 分享链接；只返回一行时按旧格式回退推导
        lines = [ln.strip() for ln in (resp.text or '').splitlines() if ln.strip()]
        download_url = lines[0] if lines else ''
        if len(lines) > 1:
            view_url = lines[1]
        else:
            view_url = download_url.replace('/d/', '/v/').rsplit('/', 1)[0] if download_url else ''

        print()
        if FileHelper.is_render_url(view_url):
            print(f'Render link:   {view_url}')
            print('               (sandboxed HTML page — safe to share)')
        else:
            print(f'View link:     {view_url}')
        print(f'Download link: {download_url}')

        bid = FileHelper.extract_id(view_url)
        if bid:
            FileHelper.print_share_hints(view_url, bid)

        if qrcode and view_url:
            print()
            self.print_qr_code_ascii(view_url)

        return True

    @staticmethod
    def check_and_print_files_size(files):
        total_size = 0
        for file_path in files:
            if os.path.isdir(file_path):
                items = Uploader.collect_bundle_items([file_path])
                if not items:
                    print(f"{file_path} 是空目录")
                    return False
                size = sum(os.stat(ap).st_size for ap, _ in items)
                total_size += size
                # 参数本身可能已经带尾斜杠（junk-file/），再拼一个就成了 // 
                print(f"{FileHelper.convert_bytes(size)}\t{file_path.rstrip('/')}/ ({len(items)} 个文件)")
                continue
            if not os.path.isfile(file_path):
                print(f"{file_path} is not a file")
                return False
            total_size += os.stat(file_path).st_size
            print(f"{FileHelper.file_size(file_path)}\t{file_path}")

        if len(files) > 1:
            print(f"{FileHelper.convert_bytes(total_size)}\ttotal")
        return True


def get_default_host():
    """获取默认服务器地址

    优先级: 环境变量 > 上次注册的服务器 > localhost:8000
    """
    env_host = os.getenv('TRANSFER_HOST')
    if env_host:
        return env_host.rstrip('/')

    last_server = TokenHolder.load_last_server()
    if last_server:
        return last_server

    return 'http://localhost:8000'


def main():
    parser = argparse.ArgumentParser(
        description='q-transfer - 文件上传工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
示例:
  q-transfer -r http://192.168.1.10:8000    # 注册授权
  q-transfer file.txt                      # 上传文件（默认启用 gzip）
  q-transfer --no-gzip image.png           # 禁用 gzip 上传
  cat data | q-transfer -n file.txt         # 管道输入并指定文件名
  p -f | q-transfer -n screenshot.png       # 剪切板图片上传
  q-transfer --list                        # 列出自己传过的包
  q-transfer --info e7ZQae0z...            # 看包详情与包内文件
  q-transfer --delete e7ZQae0z...          # 删掉整个包
  q-transfer site/ --expire 7d             # 上传并设置 7 天后过期
        '''
    )
    parser.add_argument('-r', '--register', metavar='HOST',
                        help='注册设备并授权，后跟服务器地址')
    parser.add_argument('-l', '--logout', metavar='HOST',
                        help='注销指定服务器的设备')
    parser.add_argument('files', metavar='file', type=str, nargs='*',
                        help='要上传的文件')
    parser.add_argument('-n', '--name', metavar='NAME',
                        help='管道输入时指定上传文件名')
    parser.add_argument('-y', '--yes', action='store_true',
                        help='跳过确认')
    parser.add_argument('--no-gzip', action='store_true',
                        help='禁用 gzip 压缩上传')
    parser.add_argument('--gzip-level', type=int, default=1, choices=range(1, 10),
                        help='gzip 压缩级别，1-9，默认 1')
    parser.add_argument('--bundle-name', metavar='NAME',
                        help='给这个包起个名字（列表和预览页显示它，而不是入口文件名）')
    parser.add_argument('--entry', metavar='PATH',
                        help='打包上传时的入口文件；默认不设入口（/v/{id}/ 出目录索引），'
                             '用 --entry none 也可显式表示不要入口')
    parser.add_argument('--separate', action='store_true',
                        help='多个文件也各自单传，不打包')
    parser.add_argument('-U', '--update-last', action='store_true',
                        help='原地更新「这个目录上次传过的」bundle（不用查 bundle_id）')
    parser.add_argument('--list', action='store_true',
                        help='列出自己上传的包（id / 入口 / 大小 / 下载次数 / 过期）')
    parser.add_argument('--info', metavar='BUNDLE_ID',
                        help='看某个包的详情与包内文件')
    parser.add_argument('--link', metavar='BUNDLE_ID',
                        help='只打印某个包的链接（分享/预览/整包），不上传')
    parser.add_argument('--delete', metavar='BUNDLE_ID',
                        help='删除整个包（含盘上所有文件）')
    parser.add_argument('--expire', metavar='SPEC',
                        help='上传/更新时设置过期时间：7d / 24h / 30m / never')
    parser.add_argument('--set-expire', metavar=('BUNDLE_ID', 'SPEC'), nargs=2,
                        help='修改已有包的过期时间')
    parser.add_argument('-u', '--update', metavar='BUNDLE_ID',
                        help='原地替换已有 bundle 的内容（bundle_id 不变，分享链接不变）')

    args = parser.parse_args()

    # 处理注册
    if args.register:
        auth = AuthManager(args.register)
        if auth.register():
            print(f"\n注册完成，可以开始上传文件")
        return

    # 处理注销
    if args.logout:
        token_holder = TokenHolder(args.logout)
        token_holder.clear()
        print(f"已注销 {args.logout}")
        return

    # 确定服务器地址
    # 优先使用环境变量，其次是默认值
    host = get_default_host()

    # ── 读/管理侧命令 ──
    # 必须放在「管道输入」之前：那一段会在 stdin 非 tty 时去读 stdin，
    # 于是 `q-transfer --list < /dev/null` 会直接卡死。
    if args.list or args.info or args.link or args.delete or args.set_expire:
        remote = Remote(host)
        if not remote._ready():
            return
        try:
            if args.set_expire:
                remote.set_expires(args.set_expire[0], parse_expire_spec(args.set_expire[1]))
            elif args.delete:
                remote.delete_bundle(args.delete, assume_yes=args.yes)
            elif args.info:
                remote.info(args.info)
            elif args.link:
                remote.info(args.link)
            else:
                remote.list_bundles()
        except ValueError as e:
            print(e)
        except requests.RequestException as e:
            print(f'请求失败: {e}')
        return

    # 处理管道输入
    tmp_file = None
    if not sys.stdin.isatty():
        if args.name:
            filename = os.path.basename(args.name)
            tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix='_' + filename)
            tmp_file.write(sys.stdin.buffer.read())
            tmp_file.close()
        else:
            # 先写入临时文件，再用 file 命令猜测类型
            tmp_file = tempfile.NamedTemporaryFile(delete=False)
            tmp_file.write(sys.stdin.buffer.read())
            tmp_file.close()
            mime = subprocess.run(['file', '--mime-type', '-b', tmp_file.name],
                           capture_output=True, text=True).stdout.strip()
            ext = mimetypes.guess_extension(mime) or ''
            if ext == '.jpeg':
                ext = '.jpg'
            filename = uuid.uuid4().hex[:8] + ext
            # 重命名临时文件，使路径和上传文件名一致
            new_path = os.path.join(os.path.dirname(tmp_file.name), filename)
            os.rename(tmp_file.name, new_path)
            tmp_file.name = new_path
        args.files = [tmp_file.name]
        args._pipe_filename = filename

    # 检查文件
    if not args.files:
        parser.print_help()
        return

    # -U：沿用「这个目录上次传过的」bundle。必须在 check_and_print_files_size
    # 之前解析，因为它可能补上 --entry。
    if args.update_last:
        if args.update:
            print("-U 和 -u 不能同时用：-U 是自动查 id，-u 是显式指定")
            return
        rec = BundleMap.recall(host, args.files)
        if not rec:
            print(f"没有记录：{BundleMap.key_for(args.files)} 还没从这里上传过")
            print("先 q-transfer <目录> 传一次，或显式指定 q-transfer <目录> -u <bundle_id>")
            return
        args.update = rec['bundle_id']
        if not args.entry and rec.get('entry'):
            args.entry = rec['entry']
        print(f"沿用上次的 bundle：{args.update}")

    if args.expire:
        try:
            parse_expire_spec(args.expire)
        except ValueError as e:
            print(e)
            return

    if not Uploader.check_and_print_files_size(args.files):
        return

    # 确认上传（管道模式跳过确认）
    if not args.yes and tmp_file is None:
        try:
            input(f'\n按 Enter 确认上传到 {host}')
        except (KeyboardInterrupt, EOFError):
            # 同 --delete：无 tty 时 input() 抛 EOFError，当作取消
            print()
            return

    # 上传文件
    uploader = Uploader(host)
    use_gzip = not args.no_gzip
    pipe_filename = getattr(args, '_pipe_filename', None)
    try:
        # 一个目录 / 多个文件 => 打包上传（一个「文件夹」= 一条记录）
        want_bundle = (len(args.files) > 1) or any(os.path.isdir(f) for f in args.files)
        if (want_bundle or args.update) and not args.separate and pipe_filename is None:
            if args.expire and not want_bundle:
                print("提示：--expire 只对打包上传生效，单文件走服务端默认过期时间")
            uploader.upload_bundle(args.files, entry=args.entry, qrcode=True,
                                   bundle_id=args.update,
                                   expires_at=parse_expire_spec(args.expire),
                                   name=args.bundle_name)
        else:
            for f in args.files:
                uploader.upload(f, qrcode=True, use_gzip=use_gzip, gzip_level=args.gzip_level,
                                filename=pipe_filename)
    finally:
        if tmp_file is not None:
            os.unlink(tmp_file.name)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
