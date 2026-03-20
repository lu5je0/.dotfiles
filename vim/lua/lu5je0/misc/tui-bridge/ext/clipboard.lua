local M = {}

local function_utils = require('lu5je0.lang.function-utils')

local state = {
  bridge = nil,
}

function M.setup(opts)
  state.bridge = require('lu5je0.misc.tui-bridge.tui-bridge').singleton()
  return M
end

M.input = function_utils.debounce(function(text)
  return state.bridge.call('clipboard', 'input', { text = text or '' }, { wait_response = false })
end, 1000)

function M.output(opts)
  local params = opts or { eol = 'lf' }
  local result, err = state.bridge.call('clipboard', 'output', params, { wait_response = true })
  if not result then
    return nil, err
  end
  return result.text or ''
end

return M
