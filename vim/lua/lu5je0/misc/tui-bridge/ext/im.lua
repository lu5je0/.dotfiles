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
--- Best effort on purpose: this is a fire-and-forget write to a child process we
--- own, so on exit it can occasionally be lost. Waiting for the reply would
--- block quitting, and losing it only leaves the input source where it was --
--- still switchable by hand. Also works without setup(), since a backend may
--- talk to the helper for this call alone.
function M.ascii_now()
  local bridge = state.bridge or require('lu5je0.misc.tui-bridge.tui-bridge').singleton()
  bridge.call('ime', 'normal', {}, { wait_response = false })
end

return M
