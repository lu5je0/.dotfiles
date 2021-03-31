#!/bin/bash

if [ "$1" = "-r" ] ; then
    echo "My God! Dangerous..."
    echo "Exit..."
    exit 2
else
    crontab "$1"
fi
