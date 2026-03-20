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

return M
