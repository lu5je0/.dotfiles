local M = {}

local state = {
  bridge = nil,
}

function M.setup(opts)
  state.bridge = require('lu5je0.misc.tui-bridge.tui-bridge').singleton()
  return M
end

M.input = function(text)
  return state.bridge.call('clipboard', 'input', { text = text or '' }, { wait_response = false })
end

function M.output(opts)
  local params = opts or { eol = 'lf' }
  local result, err = state.bridge.call('clipboard', 'output', params, { wait_response = true })
  if not result then
    return nil, err
  end
  return result.text or ''
end

return M
