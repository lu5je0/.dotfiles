#!/bin/bash
# DESC: download stardict?

set -euo pipefail

type curl >/dev/null 2>&1 || { echo >&2 "curl not installed. Aborting."; exit 1; }
type 7za >/dev/null 2>&1 || { echo >&2 "7za not installed. Aborting."; exit 1; }

rm -f stardict.7z stardict.7z.*
curl -L -o stardict.7z https://github.com/lu5je0/wd/releases/download/1.0/stardict.7z
7za x stardict.7z
mkdir -p "$HOME/.local/share/stardict"
mv stardict.db "$HOME/.local/share/stardict"
rm -f stardict.7z
