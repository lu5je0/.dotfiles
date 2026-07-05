#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

BLUE=$'\033[1;34m'
CYAN=$'\033[1;36m'
RESET=$'\033[0m'

printf '%s[cron]%s %s%s%s\n' "${BLUE}" "${RESET}" "${CYAN}" "${SCRIPT_DIR}/cron/spec.lua" "${RESET}"
DOTFILES_ROOT="${DOTFILES_ROOT}" TZ=UTC luajit "${SCRIPT_DIR}/cron/spec.lua"

printf '%s[line-log]%s %s%s%s\n' "${BLUE}" "${RESET}" "${CYAN}" "${SCRIPT_DIR}/line-log/spec.lua" "${RESET}"
nvim --headless -u NONE -l "${SCRIPT_DIR}/line-log/spec.lua"

printf '\n'
printf '%s[project-log]%s %s%s%s\n' "${BLUE}" "${RESET}" "${CYAN}" "${SCRIPT_DIR}/project-log/spec.lua" "${RESET}"
nvim --headless -u NONE -l "${SCRIPT_DIR}/project-log/spec.lua"

printf '\n'
printf '%s[sidebar:state]%s %s%s%s\n' "${BLUE}" "${RESET}" "${CYAN}" "${SCRIPT_DIR}/sidebar/state_spec.lua" "${RESET}"
nvim --headless -u NONE -l "${SCRIPT_DIR}/sidebar/state_spec.lua"

printf '\n'
printf '%s[sidebar]%s %s%s%s\n' "${BLUE}" "${RESET}" "${CYAN}" "${SCRIPT_DIR}/sidebar/spec.lua" "${RESET}"
nvim --headless -u NONE -l "${SCRIPT_DIR}/sidebar/spec.lua"

printf '\n'
printf '%s[sidebar:interactive]%s %s%s%s\n' "${BLUE}" "${RESET}" "${CYAN}" "${SCRIPT_DIR}/sidebar/interactive_spec.lua" "${RESET}"
nvim --headless -u NONE -l "${SCRIPT_DIR}/sidebar/interactive_spec.lua"

printf '\n'
printf '%s[sidebar:diff-preview]%s %s%s%s\n' "${BLUE}" "${RESET}" "${CYAN}" "${SCRIPT_DIR}/sidebar/diff_preview_spec.lua" "${RESET}"
nvim --headless -u NONE -l "${SCRIPT_DIR}/sidebar/diff_preview_spec.lua"

printf '\n'
printf '%s[sidebar:parser]%s %s%s%s\n' "${BLUE}" "${RESET}" "${CYAN}" "${SCRIPT_DIR}/sidebar/parser_spec.lua" "${RESET}"
nvim --headless -u NONE -l "${SCRIPT_DIR}/sidebar/parser_spec.lua"

printf '\n'
printf '%s[sidebar:git-changes]%s %s%s%s\n' "${BLUE}" "${RESET}" "${CYAN}" "${SCRIPT_DIR}/sidebar/git_changes_spec.lua" "${RESET}"
nvim --headless -u NONE -l "${SCRIPT_DIR}/sidebar/git_changes_spec.lua"

printf '\n'
printf '%s[sidebar:git-ops]%s %s%s%s\n' "${BLUE}" "${RESET}" "${CYAN}" "${SCRIPT_DIR}/sidebar/git_ops_spec.lua" "${RESET}"
nvim --headless -u NONE -l "${SCRIPT_DIR}/sidebar/git_ops_spec.lua"
