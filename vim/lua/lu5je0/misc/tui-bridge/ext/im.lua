local M = {}

local state = {
  bridge = nil
}

function M.setup()
  state.bridge = require('lu5je0.misc.tui-bridge.tui-bridge').singleton()
  return M
end

function M.normal()
  state.bridge.call('ime', 'normal', {}, { wait_response = false })
end

function M.watch(enable)
  state.bridge.call('ime', 'watch', { enable = enable }, { wait_response = false })
end

function M.on_change(handler)
  state.bridge.subscribe('ime_changed', handler)
end

function M.insert()
  state.bridge.call('ime', 'insert', {}, { wait_response = false })
end

--- Switch the input source to ASCII, for use on exit.
---
--- Uses a detached one-shot rather than the interactive helper: on exit a write
--- to our own child may never flush, and on hosts that do not otherwise run the
--- helper (kitty, where the terminal handles the IME itself) it would be
--- cold-spawned only to die immediately.
function M.ascii_now()
  require('lu5je0.misc.tui-bridge.tui-bridge').call_detached('ime', 'normal')
end

return M
