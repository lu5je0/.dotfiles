#!/bin/sh
if [ -f "$1" ]; then
    git bisect bad
else
    git bisect good
fi
