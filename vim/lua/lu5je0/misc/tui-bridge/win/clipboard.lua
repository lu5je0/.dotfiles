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

function M.input(text)
  return bridge().call('clipboard', 'input', { text = text or '' }, { wait_response = true })
end

function M.output(opts)
  local params = opts or { eol = 'lf' }
  local result, err = bridge().call('clipboard', 'output', params, { wait_response = true })
  if not result then
    return nil, err
  end
  return result.text or ''
end

return M
