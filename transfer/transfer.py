#!/usr/bin/env python3

import argparse
import os
import re
import sys
import requests
import getpass
import socket
from requests.auth import HTTPBasicAuth

from tqdm import tqdm
from tqdm.utils import CallbackIOWrapper


class HostType:
    PRIVATE = 'private'
    TRANSFER = 'transfer'

    @staticmethod
    def get_host(host_type):
        if host_type == HostType.PRIVATE:
            return 'http://{}:20404/'.format(socket.gethostbyname('sh.665665.xyz'))
        elif host_type == HostType.TRANSFER:
            return 'https://transfer.sh/'


class Cache:
    def __init__(self):
        self.token = None

    def get_token(self):
        if self.token == None:
            self.token = os.getenv('TRANSFER_PRIVATE_TOKEN')
            if self.token == None:
                self.token = getpass.getpass('token: ')
        return self.token


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


class Uploader:

    def __init__(self):
        self.cache = Cache()

    def upload(self, host_type, file_path):
        put = self.put(host_type)

        filename = os.path.basename(file_path)

        file_size = os.stat(file_path).st_size
        with open(file_path, "rb") as f:
            with tqdm(total=file_size, unit="B", unit_scale=True, unit_divisor=1024) as t:
                wrapped_file = CallbackIOWrapper(t.update, f, "read")
                resp = put(filename, data=wrapped_file)

        print('Delete command: curl --request DELETE', resp.headers['X-Url-Delete'])
        print('Delete token:', re.findall('/([^/]*?)$', resp.headers['X-Url-Delete'])[0])
        print('Download link:', resp.text)
        print()

    def put(self, host_type):
        if host_type == HostType.PRIVATE:
            token = self.cache.get_token()

            def func(filename, data=None):
                return requests.put(HostType.get_host(host_type) + filename, data=data, auth=HTTPBasicAuth(token, token))
            return func
        else:
            def func(filename, data=None):
                return requests.put(HostType.get_host(host_type) + filename, data=data)
            return func

    @staticmethod
    def check_and_print_files_size(files):
        total_size = 0
        for file_path in files:
            if not os.path.isfile(file_path):
                print(file_path, 'is not file')
                return False
            total_size += os.stat(file_path).st_size
            print(FileHelper.file_size(file_path), file_path, sep='\t')

        if len(files) > 1:
            print(FileHelper.convert_bytes(total_size), 'total', sep='\t')
        return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--private', '-p', help='private', action='store_true')
    parser.add_argument('files', metavar='file', type=str,
                        nargs='*', help='files', default=[])

    args = parser.parse_args()

    if len(args.files) == 0:
        print('files required')
        return

    if not Uploader.check_and_print_files_size(args.files):
        return

    host_type = HostType.TRANSFER
    if args.private:
        host_type = HostType.PRIVATE

    CRED = '\033[91m'
    CEND = '\033[0m'
    is_upload = input(
        CRED + 'Do you really want to upload the above files to {}? (y/n): '.format(HostType.get_host(host_type)) + CEND)
    if is_upload != 'Y' and is_upload != 'y' and is_upload != '':
        return

    uploader = Uploader()
    for f in args.files:
        uploader.upload(host_type, f)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
