-- OSC backend: proxies IME operations over OSC 1337 SetUserVar escapes using
-- the tui-bridge message format. Works with any host that understands it:
-- the local tui-bridge daemon (including over ssh, since the escape travels on
-- the pty), and kitty, which handles the same message natively and hard-disables
-- its own IME per window.
local M = {}

local function write(osc)
  if vim.fn.filewritable('/dev/fd/2') == 1 then
    return vim.fn.writefile({ osc }, '/dev/fd/2', 'b') == 0
  end
  return vim.fn.chansend(vim.v.stderr, osc) > 0
end

local function send(method)
  if vim.env.IME_DEBUG_LOG then
    local f = io.open(vim.env.IME_DEBUG_LOG, 'a')
    if f then
      f:write(('%.3f %s mode=%s\n'):format(vim.uv.hrtime() / 1e9, method, vim.api.nvim_get_mode().mode))
      f:close()
    end
  end
  local payload = string.format('{"id":1,"module":"ime","method":"%s","params":{}}', method)
  write(string.format('\27]1337;SetUserVar=%s=%s\7', 'tui-bridge', require('lu5je0.misc.base64').encode(payload)))
end

M.insert = function()
  send('insert')
end

M.normal = function()
  send('normal')
end

M.ascii_mode = function()
  M.normal()
end

--- On exit two different things have to happen, and only one of them can go
--- through the terminal:
---   1. un-bypass the IME. Mandatory -- kitty disables it outright, so leaving it
---      disabled makes the window unable to type and no input-source switch can
---      rescue it.
---   2. put the input source itself into ASCII, which kitty cannot do. Ask the
---      tui-bridge helper directly; kitty swallows the ime OSC, so that message
---      would never reach the daemon.
M.on_exit = function()
  M.insert()
  -- over ssh the helper binary lives on the other machine
  if vim.env.SSH_TTY then return end
  pcall(require('lu5je0.misc.tui-bridge.ext.im').ascii_now)
end

M.setup = function()
  return M
end

return M
