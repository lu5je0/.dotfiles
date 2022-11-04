#!/bin/bash
type unzip >/dev/null 2>&1 || { echo >&2 "unzip not installed. Aborting."; exit 1; }
type wget >/dev/null 2>&1 || { echo >&2 "wget not installed. Aborting."; exit 1; }

rm stardict.7z*
curl -L -o stardict.7z https://github.com/lu5je0/wd/releases/download/1.0/stardict.7z
7za x stardict.7z
mkdir -p ~/.local/share/stardict
mv stardict.db ~/.local/share/stardict
rm stardict.7z
