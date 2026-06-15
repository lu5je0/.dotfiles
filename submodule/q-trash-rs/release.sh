#!/bin/bash
cd "$(dirname "$0")/../.." || exit 1
git tag -f q-trash-latest
git push -f origin q-trash-latest
