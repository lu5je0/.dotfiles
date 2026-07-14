-- Shared tui-bridge IME backend for platforms that speak the tui-bridge
-- protocol (macOS and Windows/WSL). Platform differences live in the native
-- tui-bridge binary; here we only speak the normalized event contract.
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
    if args.state == 'chi' then
      handler()
    end
  end)
end

function M.setup()
  state.ime = require('lu5je0.misc.tui-bridge.ext.im').setup()
  return M
end

return M
