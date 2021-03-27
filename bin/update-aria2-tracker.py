#/usr/bin/env python3
import requests
import os
import re

resp = requests.get('https://trackerslist.com/best_aria2.txt')

aria2_config_path = os.environ['HOME'] + "/.aria2/aria2.conf"

conf = None
with open(aria2_config_path, "r") as f:
    conf = f.read()

if "bt-tracker" in conf:
    conf = re.sub("bt-tracker=.*?", "bt-tracker=" + resp.text, conf)
else:
    conf = conf + "\nbt-tracker=" + resp.text + "\n"

print(conf)
with open(aria2_config_path, "w+") as f:
    f.write(conf)
