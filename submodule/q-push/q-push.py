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

    token = os.environ.get("FEISHU_TOKEN", "").strip()
    if token == "":
        print("feishu token is missing: FEISHU_TOKEN")
        sys.exit(1)
    
    resp = requests.post(
        'https://open.feishu.cn/open-apis/bot/v2/hook/' + token,
        headers=headers,
        json=json_data,
    )
    if resp.status_code != 200:
        print('push failed', resp)

if __name__ == "__main__":
    text = ""
    
    parser = argparse.ArgumentParser()
    parser.add_argument('msgs', nargs='*')
    # parser.add_argument("-i", "--img")
    args = parser.parse_args()
    
    if args.msgs == [] and sys.stdin.isatty():
        print("Error: At least one msg is required.")
        parser.print_usage()
        sys.exit(1)
    
    if args.msgs != []:
        text = "\n".join(args.msgs)

    if not sys.stdin.isatty():
        text = text + "\n\n" + "".join(sys.stdin.readlines())

    if text != "": 
        push(text)
