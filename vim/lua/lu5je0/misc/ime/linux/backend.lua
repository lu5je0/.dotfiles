-- Linux / fcitx5 + rime backend.
--
-- Toggles rime's own Chinese/English mode (ascii_mode) via dbus so we
-- don't disable the whole IM. This mirrors Shift's behaviour in rime
-- and preserves candidates, schema, punctuation mode, etc.
--
-- To keep vim responsive we never block on dbus:
--   - IsAsciiMode is queried asynchronously via jobstart+on_stdout, its
--     result is cached in last_ime_chinese for the next InsertEnter.
--   - SetAsciiMode is fired-and-forgotten via detached jobstart.
local M = {}

local last_ime_chinese = false

local DEST = 'org.fcitx.Fcitx5'
local OBJ = '/rime'
local IFACE = 'org.fcitx.Fcitx.Rime1'

local function set_ascii_mode(ascii)
  vim.fn.jobstart({
    'busctl', 'call', '--user',
    DEST, OBJ, IFACE, 'SetAsciiMode', 'b', ascii and '1' or '0',
  }, { detach = true })
end

local function query_ascii_mode(cb)
  vim.fn.jobstart({
    'busctl', 'call', '--user',
    DEST, OBJ, IFACE, 'IsAsciiMode',
  }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local ascii = false
      for _, line in ipairs(data or {}) do
        if line:find('true', 1, true) then ascii = true; break end
      end
      cb(ascii)
    end,
  })
end

function M.normal()
  query_ascii_mode(function(ascii)
    last_ime_chinese = not ascii
    if last_ime_chinese then
      set_ascii_mode(true)
    end
  end)
end

function M.insert()
  if last_ime_chinese then
    set_ascii_mode(false)
  end
end

function M.ascii_mode()
  set_ascii_mode(true)
end

--- Quitting hands the terminal back to the shell, so leave rime in English.
--- busctl is spawned detached, so it still completes as we go away.
function M.on_exit()
  M.ascii_mode()
end

function M.setup()
  return M
end

return M
