local M = {}

local state = {
  bridge = nil,
}

local function bridge()
  if not state.bridge then
    state.bridge = require('lu5je0.misc.tui-bridge.tui-bridge').setup()
  end
  return state.bridge
end

function M.setup(opts)
  state.bridge = require('lu5je0.misc.tui-bridge.tui-bridge').setup(opts)
  return M
end

function M.normal()
  bridge().call('ime', 'normal', {}, { wait_response = false })
end

function M.insert()
  bridge().call('ime', 'insert', {}, { wait_response = false })
end

return M
