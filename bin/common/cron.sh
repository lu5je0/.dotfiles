#!/bin/bash

if [ "$1" = "-r" ] ; then
    echo "My God! Dangerous..."
    echo "Exit..."
    exit 2
elif [ -z "$1" ] ; then
    echo "Usage: cron.sh <crontab-file>" >&2
    exit 1
else
    crontab "$1"
fi
