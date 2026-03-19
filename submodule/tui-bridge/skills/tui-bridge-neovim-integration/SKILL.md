---
name: tui-bridge-neovim-integration
description: Use when modifying tui-bridge together with its Neovim integration in this dotfiles repo, especially for IME or clipboard behavior on macOS/WSL. Covers where the bridge is launched, which Lua modules consume it, how Windows and macOS differ, and what to rebuild/update after changes.
---

# tui-bridge Neovim Integration

Use this skill when a task touches both the `tui-bridge` submodule and the Neovim config that consumes it.

If the current environment does not expose this repository skill as an installed/available skill, treat this file as a local workflow guide and follow it manually.

## When to use
- Changing `ime.normal`, `ime.insert`, `ime.watch`, IME event payloads, or clipboard methods.
- Updating Windows/macOS platform behavior and checking the Neovim side still matches.
- Rebuilding `tui_bridge` and syncing it into `vim/lib/<platform>/bin/`.
- Auditing whether `AGENTS.md` needs updates after bridge behavior changes.

## Source of truth
- Protocol and platform behavior: `submodule/tui-bridge/AGENTS.md`
- Bridge process wrapper in Neovim: `vim/lua/lu5je0/misc/tui-bridge/tui-bridge.lua`
- IME wrappers: `vim/lua/lu5je0/misc/tui-bridge/ext/im.lua`
- Clipboard wrappers: `vim/lua/lu5je0/misc/tui-bridge/ext/clipboard.lua`
- Common IME keeper logic: `vim/lua/lu5je0/misc/im/im.lua`
- Platform IME adapters:
  - `vim/lua/lu5je0/misc/im/mac/ime-control.lua`
  - `vim/lua/lu5je0/misc/im/win/ime-control.lua`
- WSL clipboard provider: `vim/lua/lu5je0/misc/clipboard/wsl.lua`
- Neovim option wiring: `vim/lua/lu5je0/options.lua`

## Current integration shape
- Neovim launches `tui_bridge` from platform-specific paths under `stdpath('config') .. '/lib/'`.
- IME logic is split into:
  - platform adapter: how to switch/query behavior on that OS
  - common keeper logic in `misc/im/im.lua`: autocmds, watch subscription, normalization decision flow
- Clipboard on WSL uses `clipboard.output/input` through `misc/clipboard/wsl.lua`.

## Platform semantics
- macOS:
  - `ime.watch` emits `ime_changed` with a real `source_id` input-source ID.
  - keeper normalization checks whether `source_id` is not `com.apple.keylayout.ABC`.
- Windows:
  - `ime.watch` tracks Chinese IME internal eng/chi state, not TSF input-source identity.
  - events currently include both `state` and `source_id`, and `source_id` is only a compatibility alias of `state`.
  - Neovim should prefer `args.state` and only fall back to `args.source_id` for compatibility.

## Working rules
- If bridge protocol, event payloads, platform semantics, build flow, or Neovim integration points change, update `submodule/tui-bridge/AGENTS.md` in the same task.
- Keep common keeper/autocmd logic in `vim/lua/lu5je0/misc/im/im.lua`; avoid duplicating it into both mac/win adapters.
- Keep platform adapters thin. They should only own platform-specific IME operations and platform-specific normalization checks.
- Prefer rebuilding via `submodule/tui-bridge/build.sh [output]`.
- In WSL, the default build still builds in Windows temp and syncs the result to `vim/lib/windows/bin/tui_bridge`.
- For macOS changes, ensure the rebuilt binary ends up in `vim/lib/macos/bin/tui_bridge`.

## Minimal validation checklist
- Lua syntax:
  - `luac -p vim/lua/lu5je0/misc/im/im.lua`
  - `luac -p vim/lua/lu5je0/misc/im/mac/ime-control.lua`
  - `luac -p vim/lua/lu5je0/misc/im/win/ime-control.lua`
- Windows watch request smoke test:
  - `./tui_bridge -j '{"id":1,"module":"ime","method":"watch","params":{"enable":true}}'`
  - This only verifies that the request shape is accepted and watch initialization does not fail immediately.
- Interactive watch check when relevant:
  - `./tui_bridge -i`
  - send `{"id":1,"module":"ime","method":"watch","params":{"enable":true}}`
  - then toggle IME state manually on Windows and inspect emitted events
  - Use this path, not `-j`, to validate that `ime_changed` events actually stream back to the client

## Common pitfalls
- Do not assume Windows `source_id` is a real input-method identifier.
- Do not move platform-specific heuristics into the common IME module.
- Do not update bridge behavior without syncing Neovim consumer logic and `AGENTS.md`.
