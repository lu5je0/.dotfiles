-- Windows / WSL backend: delegates to tui-bridge's IME extension.
local M = {}

local state = { ime = nil }

function M.normal()
  state.ime.normal()
end

function M.insert()
  state.ime.insert()
end

M.ascii_mode = function()
  M.normal()
end

function M.keeper(enable)
  state.ime.watch(enable == true)
end

function M.on_change(handler)
  state.ime.on_change(function(args)
    local ime_state = args.state or args.source_id
    if ime_state == 'chi' then
      handler()
    end
  end)
end

function M.setup()
  state.ime = require('lu5je0.misc.tui-bridge.ext.im').setup()
  return M
end

return M
