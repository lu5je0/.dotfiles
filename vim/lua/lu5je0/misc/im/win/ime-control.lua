local M = {}

local state = {
  ime = nil
}

function M.normal()
  state.ime.normal()
end

function M.insert()
  state.ime.insert()
end

M.switch_en = function()
  M.normal()
end

function M.keeper(enable)
  state.ime.watch(enable == true)
end

function M.on_change(handler)
  state.ime.on_change(handler)
end

function M.should_normalize(args)
  local ime_state = args.state or args.source_id
  return ime_state == 'chi'
end

function M.setup()
  state.ime = require('lu5je0.misc.tui-bridge.ext.im').setup()
  return M
end

return M
