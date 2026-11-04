-- OSC backend: proxies IME operations over OSC 1337 SetUserVar escapes using
-- the tui-bridge message format. Works with any host that understands it:
-- the local tui-bridge daemon (including over ssh, since the escape travels on
-- the pty), and kitty, which handles the same message natively and hard-disables
-- its own IME per window.
local M = {}

-- Queue escapes with the TUI renderer so they cannot interleave with a partial
-- screen update. This is the same path Neovim's built-in OSC 52 backend uses.
local function write(osc)
  vim.api.nvim_ui_send(osc)
end

-- tmux consumes OSC 1337 instead of forwarding it, so inside tmux the escape has
-- to travel in a DCS passthrough wrapper with every inner ESC doubled. Requires
-- `set -g allow-passthrough on` (tmux/tmux.conf).
local function tmux_wrap(osc)
  return '\27Ptmux;' .. (osc:gsub('\27', '\27\27')) .. '\27\\'
end

-- There are only ever two payloads, so encode them once instead of formatting
-- and base64-ing the same strings on every mode change.
local OSC = {}
for _, method in ipairs { 'normal', 'insert' } do
  local payload = string.format('{"id":1,"module":"ime","method":"%s","params":{}}', method)
  local osc = string.format('\27]1337;SetUserVar=tui-bridge=%s\7', require('lu5je0.misc.base64').encode(payload))
  OSC[method] = vim.env.TMUX and tmux_wrap(osc) or osc
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

-- Most hosts switch the input source through OSC. Kitty instead uses OSC to
-- bypass IME, so it needs insert to undo that bypass, followed by a detached
-- local backend request to switch the actual input source to English.
M.on_exit = function()
  if vim.env.TERM ~= 'xterm-kitty' then
    -- The host executes the request, including over SSH. Restoring insert here
    -- would bring back the saved Chinese input source in WezTerm.
    M.normal()
    return
  end
  M.insert()
  -- over ssh the helper binary lives on the other machine
  if vim.env.SSH_TTY then
    return
  end
  require('lu5je0.misc.tui-bridge.ext.im').ascii_now()
end

M.setup = function()
  if vim.env.TERM == 'xterm-kitty' and not vim.env.SSH_TTY then
    require('lu5je0.misc.tui-bridge.installer').default().ensure()
  end
  return M
end

return M
