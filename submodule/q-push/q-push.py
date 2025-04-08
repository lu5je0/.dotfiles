import requests
import argparse
import os
import sys

def push(text: str):
    headers = {
        'Content-Type': 'application/json',
    }

    json_data = {
        'msg_type': 'text',
        'content': {
            'text': text,
        },
    }

    if 'FEISHU_TOKEN' not in os.environ:
        print("feishu token is missing")
        return
    token = os.environ['FEISHU_TOKEN']
    
    resp = requests.post(
        'https://open.feishu.cn/open-apis/bot/v2/hook/' + token,
        headers=headers,
        json=json_data,
    )
    if resp.status_code != 200:
        print('push failed', resp)

if __name__ == "__main__":
    text = None
    if sys.stdin.isatty():
        parser = argparse.ArgumentParser()
        parser.add_argument('msgs', nargs='+')
        # parser.add_argument("-i", "--img")
        args = parser.parse_args()
        text = "\n".join(args.msgs)
    else:
        text = "".join(sys.stdin.readlines())

    if text != None: 
        push(text)
