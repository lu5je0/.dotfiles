-- Per-tabpage sidebar state.
--
-- Exposes a metatable proxy so callers can write `state.files.x` and
-- have it routed to the current tab's table. For async callbacks that
-- might fire on a different tabpage, capture `state.tab()` first and
-- access the snapshot directly.
--
-- The full per-tab schema lives in `new_tab_state()` below. New per-tab
-- fields MUST be declared there so the shape is discoverable in one
-- place and the source dispose hook can free any resources it owns.
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

local function new_tab_state(tabpage)
  return {
    tabpage = tabpage,
    source_generation = 0,
    source_context = nil,
    disposed = false,

    -- window / buffer
    win = nil,
    buf = nil,
    width = 33,
    last_width = nil,

    -- winbar tabs
    active_tab_idx = 1,
    tab_cursors = {},
    visible_tabs = {},
    tab_widths = {},
    _visible_start = 1,

    git_status = {
      timer = nil,
      generation = 0,
      callbacks = {},
      running = nil,
      pending = false,
      stdout = nil,
      cwd = nil,
    },

    files = {
      root = nil,
      display_items = {},
      hide_dotfiles = true,
      compress_dirs = false,
      git_status_map = {},
      git_root = nil,
      reveal_path = nil,
      live_filter = nil,

      -- caches
      _root_cache = {},
      _cursor_cache = {},

      -- libuv handles owned by this tab
      fs_watchers = {},
      fs_refresh_timer = nil,

      -- live_filter overlay
      _live_filter = {
        buf = nil,
        win = nil,
        closing = false,
      },

      -- clipboard mark for cut/copy/paste in files source
      _clipboard = nil,
    },

    git_changes = {
      sections = {},
      display_items = {},
      _expanded = nil,        -- { changes, staged, unstaged, untracked, stashes } — lazily populated
      _dir_states = nil,      -- per-section { [abs_path] = bool }
      _stash_entries = nil,   -- { { ref, message, expanded, children, _files_loaded } }
      _undo_stack = nil,      -- list of undo entries pushed by git_ops
      _redo_stack = nil,      -- list of redo entries for redo support
      _last_git_root = nil,
      stash_jobs = {},
      _is_loading = false,
      _first_located = false,   -- first <leader>gs entry on this tabpage parks on the first changed file
    },

    history = {
      repo_root = nil,
      graph_enabled = false,
      graph_rows = nil,
      commits = {},
      display_items = {},
      selected_commits = {},
      log_buf = nil,
      log_win = nil,
      refresh_selection = nil,
      is_visible = nil,
      loaded = false,
      loading = false,
      error = nil,
      limited = false,
      generation = 0,
      job = nil,
      count_job = nil,
      merge_jobs = {},
      pending_jump_sha = nil,
      pending_jump_file = nil,
    },

    -- Watcher resources belong to the tabpage, not the selected source.
    _index_watcher = nil,
    _index_path = nil,

    buffers = {
      display_items = {},
    },

    symbols = {
      nodes = {},
      display_items = {},
      target_buf = nil,
      last_located_node = nil,
      generation = 0,
      cancel_request = nil,
      follow_timer = nil,
      last_follow_line = nil,
      auto_follow = nil,
      _is_empty = false,
    },

    preview = {
      generation = 0,
      active = false,
      enter_pending = false,
      text_win = nil,
      text_buf = nil,
      text_autocmd = nil,
      autocmd = nil,
      bufleave_autocmd = nil,
      type = nil,
    },

    -- diff_preview floating windows (dual mode uses left/right, single mode uses win_single)
    diff_preview = {
      generation = 0,
      timer = nil,
      win_left = nil,
      win_right = nil,
      buf_left = nil,
      buf_right = nil,
      win_single = nil,
      buf_single = nil,
      refresh = nil,
    },
  }
end

local function get_tab_state()
  local tab = vim.api.nvim_get_current_tabpage()
  if not _tabs[tab] then
    _tabs[tab] = new_tab_state(tab)
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
  for tp, ts in pairs(_tabs) do
    if not valid[tp] then
      require('lu5je0.ext.sidebar.lifecycle').dispose(ts)
      _tabs[tp] = nil
    end
  end
end

--- Return the state table for an arbitrary tabpage handle (creating it if
--- necessary). Used by async callbacks that captured a tabpage handle and
--- need to write into that specific tab without going through the proxy.
function M.tab_for(tabpage)
  if not _tabs[tabpage] then
    _tabs[tabpage] = new_tab_state(tabpage)
  end
  return _tabs[tabpage]
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
  tab_for = true,
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
