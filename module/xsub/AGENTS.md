# AGENTS

## Overview

- This repo provides `xsub`, a small CLI for extracting text subtitles from MKV files and rewriting them into templated `.ass` output.
- The project is intended to be run with `uv`.
- Built-in ASS templates live in `template/`.

## Commands

- Install dependencies: `uv sync`
- Run the CLI locally: `uv run python xsub.py ...`
- Common checks:
  - `python3 xsub.py convert -h`
  - `python3 xsub.py extract -h`

## Behavior Notes

- Auto extract mode prefers Simplified Chinese subtitles, then falls back to other Chinese subtitles.
- Auto extract mode prefers full English subtitles over `forced` English subtitles.
- In dual-track extract mode, Chinese and English blocks are flattened internally to one line each, with a single line break kept between Chinese and English.
- `--split-zh-and-en-lines` only affects single-track mixed-language subtitles.
- `--no-english-standalone-font` disables the `Eng` style for English text in both single-track and dual-track output.

## Editing Notes

- Built-in templates are loaded from the repo-local `template/` directory.
- Prefer minimal CLI surface changes and keep help text aligned with actual behavior.
- Validate subtitle selection changes with reproducible track metadata or temporary media fixtures. Local videos can supplement these checks.
- Extraction writes `.ass` files next to the input by default; use temporary inputs for tests.
