#/usr/bin/env python3
import requests
import os

resp = requests.get('https://trackerslist.com/best_aria2.txt')

aria2_config_path = os.environ['HOME'] + "/.aria2/aria2.conf"

conf = None
with open(aria2_config_path, "r") as f:
    conf = f.read()

if "bt-tracker" in conf:
    conf.replace("bt-tracker=.*", "bt-tracker=123231")
else:
    conf = conf + "\nbt-tracker=" + resp.text + "\n"

with open(aria2_config_path, "w+") as f:
    f.write(conf)
