#!/usr/bin/python3
import croniter
import datetime
import sys
import argparse

def parse_crontab(s, count):
    now = datetime.datetime.now()
    cron = croniter.croniter(s, now)
   
    for _ in range(count):
        print(cron.get_next(datetime.datetime))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--count', default=10, type=int)
    if not sys.stdin.isatty():
        parser.add_argument('stdin', nargs='?', default=sys.stdin)

        args = parser.parse_args()
        stdin = parser.parse_args().stdin.read().splitlines()
        parse_crontab(stdin[0], args.count)
    else:
        parser.add_argument('crontab', type=str)
        args = parser.parse_args()
        parse_crontab(args.crontab, args.count)
