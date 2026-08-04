-- OSC backend: proxies IME operations over OSC 1337 SetUserVar escapes using
-- the tui-bridge message format. Works with any host that understands it:
-- the local tui-bridge daemon (including over ssh, since the escape travels on
-- the pty), and kitty, which handles the same message natively and hard-disables
-- its own IME per window.
local M = {}

-- fd 2 is the terminal. C stderr is unbuffered, so this lands immediately while
-- avoiding the vim.fn bridge and the open/close that writefile('/dev/fd/2') does
-- per call -- measured 0.5us against 22us for that.
local function write(osc)
  io.stderr:write(osc)
end

-- There are only ever two payloads, so encode them once instead of formatting
-- and base64-ing the same strings on every mode change.
local OSC = {}
for _, method in ipairs({ 'normal', 'insert' }) do
  local payload = string.format('{"id":1,"module":"ime","method":"%s","params":{}}', method)
  OSC[method] = string.format('\27]1337;SetUserVar=tui-bridge=%s\7',
    require('lu5je0.misc.base64').encode(payload))
end

-- Read once: an env var cannot change mid-session, and vim.env goes through a
-- metatable that costs more than the write itself.
local debug_log = vim.env.IME_DEBUG_LOG

local function send(method)
  if debug_log then
    local f = io.open(debug_log, 'a')
    if f then
      f:write(('%.3f %s mode=%s\n'):format(vim.uv.hrtime() / 1e9, method, vim.api.nvim_get_mode().mode))
      f:close()
    end
  end
  write(OSC[method])
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
