#!/usr/bin/env python3
"""
q-transfer - 文件上传客户端

使用浏览器授权流程:
1. 运行 q-transfer -r <host> 注册设备
2. 按提示打开浏览器授权
3. 授权后即可上传文件

示例:
    q-transfer -r http://transfer.com:8000    # 注册授权
    q-transfer file.txt                        # 上传文件（默认启用 gzip）
    q-transfer --no-gzip image.png            # 禁用 gzip 上传
"""

import argparse
import os
import platform
import sys
import time
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


class FileHelper:
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

    def upload(self, file_path, qrcode=True, use_gzip=True, gzip_level=1):
        """上传单个文件"""
        # 确保已授权
        if not self.auth.ensure_authorized():
            return False

        filename = os.path.basename(file_path)
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
        download_url = resp.text.strip()
        # 构建预览链接: /d/{file_id}/{filename} -> /v/{file_id}
        view_url = download_url.replace('/d/', '/v/').rsplit('/', 1)[0] if download_url else ''
        
        print(f'\nView link:    {view_url}')
        print(f'Download link: {download_url}')

        if qrcode and view_url:
            print()
            self.print_qr_code_ascii(view_url)

        return True

    @staticmethod
    def check_and_print_files_size(files):
        total_size = 0
        for file_path in files:
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
  q-transfer -r http://192.168.1.3:8000    # 注册授权
  q-transfer file.txt                        # 上传文件（默认启用 gzip）
  q-transfer --no-gzip image.png            # 禁用 gzip 上传
        '''
    )
    parser.add_argument('-r', '--register', metavar='HOST',
                        help='注册设备并授权，后跟服务器地址')
    parser.add_argument('-l', '--logout', metavar='HOST',
                        help='注销指定服务器的设备')
    parser.add_argument('files', metavar='file', type=str, nargs='*',
                        help='要上传的文件')
    parser.add_argument('-y', '--yes', action='store_true',
                        help='跳过确认')
    parser.add_argument('--no-gzip', action='store_true',
                        help='禁用 gzip 压缩上传')
    parser.add_argument('--gzip-level', type=int, default=1, choices=range(1, 10),
                        help='gzip 压缩级别，1-9，默认 1')

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

    # 检查文件
    if not args.files:
        parser.print_help()
        return

    if not Uploader.check_and_print_files_size(args.files):
        return

    # 确认上传
    if not args.yes:
        try:
            input(f'\n按 Enter 确认上传到 {host}')
        except KeyboardInterrupt:
            print()
            return

    # 上传文件
    uploader = Uploader(host)
    use_gzip = not args.no_gzip
    for f in args.files:
        uploader.upload(f, qrcode=True, use_gzip=use_gzip, gzip_level=args.gzip_level)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
