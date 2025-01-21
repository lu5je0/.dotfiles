#!/usr/bin/python3
import subprocess, os

if not os.path.exists(".git"):
    print("No git repository. Nothing was changed.")
    exit()

info = (subprocess.check_output(["git", "remote", "-v"])).decode('UTF-8').split()

remote_name = info[0]
remote_address = info[1]

if remote_address[0:3] == "git":
    print("Remote address already set to ssh. Nothing was changed.")
    exit()

[old_protocol, _, domain, user, rep] = remote_address.split('/')
if rep[-4:] == ".git":
    rep = rep[:-4]

new_remote = 'git@' + domain + ':' + user + '/' + rep + ".git"
subprocess.call(["git", "remote", "set-url", remote_name, new_remote])
print("Changed remote address of " + remote_name +" from " + remote_address + " to " + new_remote + ".")
