#!/usr/bin/env python3

import os
from threading import Thread
import time
import sys


def run_on(port):
    os.system("python3 -m http.server " + str(port))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        port = 20080
    else:
        port = int(sys.argv[1])
    server = Thread(target=run_on, args=[port])
    server.start()
