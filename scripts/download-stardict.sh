wget https://github.com/skywind3000/ECDICT/releases/download/1.0.28/ecdict-sqlite-28.zip

if [[ ! -d ~/.misc ]]; then
    mkdir ~/.misc
fi
unzip ecdict-sqlite-28.zip
mv stardict.db ~/.misc/
rm ecdict-sqlite-28.zip
