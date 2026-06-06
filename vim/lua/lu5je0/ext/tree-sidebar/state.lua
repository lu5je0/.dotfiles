-- Per-tabpage sidebar state.
--
-- Exposes a metatable proxy so callers can write `state.files.x` and
-- have it routed to the current tab's table. For async callbacks that
-- might fire on a different tabpage, capture `state.tab()` first and
-- access the snapshot directly.
local Stack = require('lu5je0.lang.stack')

local M = {}

-- ── globals (shared across tabpages) ───────────────────

M.pwd_stack = Stack:create()
M.pwd_forward_stack = Stack:create()
M._is_jumping = false
M._last_pushed_cwd = nil

function M.pwd_stack_push()
  if M._is_jumping then return end
  local cwd = vim.fn.getcwd()
  if M._last_pushed_cwd ~= cwd then
    M.pwd_stack:push(cwd)
    M._last_pushed_cwd = cwd
  end
end

function M.init_pwd_stack()
  local cwd = vim.fn.getcwd()
  M.pwd_stack:push(cwd)
  M._last_pushed_cwd = cwd
end

-- ── per-tabpage state ──────────────────────────────────

local _tabs = {}

local function new_tab_state()
  return {
    win = nil,
    buf = nil,
    width = 33,
    last_width = nil,
    active_tab_idx = 1,
    tab_cursors = {},
    files = {
      root = nil,
      display_items = {},
      hide_dotfiles = true,
      git_status_map = {},
      reveal_path = nil,
      live_filter = nil,
    },
    git_changes = {
      sections = {},
      display_items = {},
    },
    buffers = {
      display_items = {},
    },
    symbols = {
      nodes = {},
      display_items = {},
      target_buf = nil,
    },
  }
end

local function get_tab_state()
  local tab = vim.api.nvim_get_current_tabpage()
  if not _tabs[tab] then
    _tabs[tab] = new_tab_state()
  end
  return _tabs[tab]
end

--- Return the current tabpage's state table directly. Use this in
--- async callbacks to avoid the metatable proxy crossing tabpages.
function M.tab()
  return get_tab_state()
end

function M.cleanup_closed_tabs()
  local valid = {}
  for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
    valid[tp] = true
  end
  for tp, _ in pairs(_tabs) do
    if not valid[tp] then _tabs[tp] = nil end
  end
end

-- ── proxy: M.<x> routes to per-tab state ───────────────

local _global_keys = {
  pwd_stack = true,
  pwd_forward_stack = true,
  _is_jumping = true,
  _last_pushed_cwd = true,
}

local _methods = {
  is_open = true,
  is_buf_valid = true,
  pwd_stack_push = true,
  init_pwd_stack = true,
  cleanup_closed_tabs = true,
  tab = true,
}

setmetatable(M, {
  __index = function(self, key)
    if _global_keys[key] or _methods[key] then
      return rawget(self, key)
    end
    return get_tab_state()[key]
  end,
  __newindex = function(self, key, value)
    if _global_keys[key] or _methods[key] then
      rawset(self, key, value); return
    end
    get_tab_state()[key] = value
  end,
})

function M.is_open()
  local ts = get_tab_state()
  return ts.win ~= nil and vim.api.nvim_win_is_valid(ts.win)
end

function M.is_buf_valid()
  local ts = get_tab_state()
  return ts.buf ~= nil and vim.api.nvim_buf_is_valid(ts.buf)
end

return M
