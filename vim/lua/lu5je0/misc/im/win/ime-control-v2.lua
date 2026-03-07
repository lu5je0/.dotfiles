local M = {}

local state = {
  ime = nil,
  opts = nil,
}

local function ensure_ime()
  if state.ime then
    return state.ime
  end
  local bridge = require('lu5je0.misc.tui-bridge.win.im').setup(state.opts)
  state.ime = bridge
  return state.ime
end

function M.normal()
  ensure_ime().normal()
end

function M.insert()
  ensure_ime().insert()
end

function M.setup(opts)
  state.opts = opts or {}
  ensure_ime()
  return M
end

return M
