local M = {}

local state = {
  bridge = nil,
}

function M.setup(opts)
  state.bridge = require('lu5je0.misc.tui-bridge.tui-bridge').singleton()
  return M
end

--- opts.selection: 'regular'（默认，CLIPBOARD/`+`）或 'primary'（`*`）。
M.input = function(text, opts)
  local params = { text = text or '' }
  if opts and opts.selection then
    params.selection = opts.selection
  end
  return state.bridge.call('clipboard', 'input', params, { wait_response = false })
end

function M.output(opts)
  local params = opts or { eol = 'lf' }
  local result, err = state.bridge.call('clipboard', 'output', params, { wait_response = true })
  if not result then
    return nil, err
  end
  return result.text or ''
end

function M.output_async(opts, callback)
  local params = opts or { eol = 'lf' }
  state.bridge.call('clipboard', 'output', params, {
    callback = function(result, err)
      if not result then
        callback(nil, err)
      else
        callback(result.text or '')
      end
    end,
  })
end

return M
