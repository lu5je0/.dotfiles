# AGENTS

## Overview

- This repo provides `q-xsub`, a small CLI for extracting text subtitles from MKV files and rewriting them into templated `.ass` output.
- The project is intended to be run with `uv`.
- Built-in ASS templates live in `template/`.

## Commands

- Install dependencies: `uv sync`
- Run the CLI locally: `uv run python q_xsub.py ...`
- Common checks:
  - `python3 q_xsub.py convert -h`
  - `python3 q_xsub.py extract -h`

## Behavior Notes

- Auto extract mode prefers Simplified Chinese subtitles, then falls back to other Chinese subtitles.
- Auto extract mode prefers full English subtitles over `forced` English subtitles.
- In dual-track extract mode, Chinese and English blocks are flattened internally to one line each, with a single line break kept between Chinese and English.
- `--split-zh-and-en-lines` only affects single-track mixed-language subtitles.
- `--no-english-standalone-font` disables the `Eng` style for English text in both single-track and dual-track output.

## Editing Notes

- Keep templates repo-local under `template/`; do not reintroduce dependency on `~/.dotfiles/submodule/pyass/template`.
- Prefer minimal CLI surface changes and keep help text aligned with actual behavior.
- When changing subtitle selection rules, validate against the sample file:
  - `/mnt/mg08/videos/tv/黑袍纠察队 (2019)/S05/01.mkv`

## Sandbox Notes

- Real subtitle extraction may write `.ass` output next to MKV files outside the repo. That requires escalated execution in this environment.
- `uv run q-xsub ...` may fail unless the entrypoint is installed; `uv run python q_xsub.py ...` is the reliable repo-local invocation.
