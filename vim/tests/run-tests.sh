#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

DOTFILES_ROOT="${DOTFILES_ROOT}" TZ=UTC luajit "${SCRIPT_DIR}/cron-parser_spec.lua"
nvim --headless -u NONE -l "${SCRIPT_DIR}/line-log_spec.lua"
