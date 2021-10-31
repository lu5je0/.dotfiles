#!/bin/bash
type unzip >/dev/null 2>&1 || { echo >&2 "unzip not installed. Aborting."; exit 1; }
type wget >/dev/null 2>&1 || { echo >&2 "wget not installed. Aborting."; exit 1; }

rm ecdict-sqlite-28.zip*
wget https://github.com/skywind3000/ECDICT/releases/download/1.0.28/ecdict-sqlite-28.zip
mkdir ~/.misc
unzip ecdict-sqlite-28.zip
mv stardict.db ~/.misc/
rm ecdict-sqlite-28.zip
