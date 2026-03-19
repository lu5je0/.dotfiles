local M = {}

local state = {
  ime = nil,
  opts = nil,
}

local function ensure_ime()
  if state.ime then
    return state.ime
  end
  local bridge = require('lu5je0.misc.tui-bridge.ext.im').setup(state.opts)
  state.ime = bridge
  return state.ime
end

function M.normal()
  ensure_ime().normal()
end

function M.insert()
  ensure_ime().insert()
end

function M.keeper(enable)
  local ime = ensure_ime()
  ime.watch(enable == true)
end

function M.on_change(handler)
  ensure_ime().on_change(handler)
end

function M.should_normalize(args)
  local ime_state = args.state or args.source_id
  return ime_state == 'chi'
end

function M.setup(opts)
  state.opts = opts or {}
  ensure_ime()
  return M
end

return M
