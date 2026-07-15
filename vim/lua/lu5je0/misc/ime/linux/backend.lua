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
--
-- Keeper: rime does not emit dbus signals for ascii_mode toggles (Shift
-- flips it internally), so we simulate an on_change signal by polling
-- IsAsciiMode on a libuv timer while the keeper is enabled and firing
-- the registered handler when the state changes. init.lua's handler
-- decides whether to force English via ascii_mode(); this backend just
-- reports state, matching the mac/win interface shape.
local M = {}

local last_ime_chinese = false

local DEST = 'org.fcitx.Fcitx5'
local OBJ = '/rime'
local IFACE = 'org.fcitx.Fcitx.Rime1'

local KEEPER_INTERVAL_MS = 800

local keeper_state = {
  timer = nil,
  in_flight = false,
  last_ascii = nil,
}

local change_handler = nil

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

local function stop_keeper_timer()
  local t = keeper_state.timer
  if t then
    pcall(function() t:stop() end)
    pcall(function() t:close() end)
    keeper_state.timer = nil
  end
  keeper_state.last_ascii = nil
end

local function poll_once()
  if keeper_state.in_flight then return end
  keeper_state.in_flight = true
  query_ascii_mode(function(ascii)
    keeper_state.in_flight = false
    last_ime_chinese = not ascii
    if change_handler and not ascii and keeper_state.last_ascii ~= ascii then
      change_handler()
    end
    keeper_state.last_ascii = ascii
  end)
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

function M.keeper(enable)
  stop_keeper_timer()
  if not enable then return end
  local timer = vim.uv.new_timer()
  if not timer then return end
  keeper_state.timer = timer
  timer:start(KEEPER_INTERVAL_MS, KEEPER_INTERVAL_MS, vim.schedule_wrap(poll_once))
end

function M.on_change(handler)
  change_handler = handler
end

function M.setup()
  return M
end

return M
