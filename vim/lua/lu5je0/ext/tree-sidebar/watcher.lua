-- Unified fs_event watchers for the tree-sidebar.
--
-- Manages two kinds of watchers:
-- 1. File tree directory watchers: one per expanded directory, synced on render
-- 2. .git/index watcher: one per tabpage, covers stage/commit/stash etc.
--
-- Handles and timers live in per-tab state so each tabpage owns its own
-- resources. Consumers register callbacks at module load time:
--   M.on_files_changed(tabpage)  — set by files/init.lua
--   M.on_index_changed(tabpage)  — set by git_changes/init.lua
local state = require('lu5je0.ext.tree-sidebar.state')

local M = {}

local DEBOUNCE_MS = 300

M.on_files_changed = function(_tabpage) end
M.on_index_changed = function(_tabpage) end

-- ── helpers ────────────────────────────────────────────

local function close_handle(h)
  pcall(function() h:stop() end)
  pcall(function() h:close() end)
end

local function close_timer(timer)
  if not timer then return end
  pcall(function() timer:stop() end)
  pcall(function() timer:close() end)
end

-- ── file tree directory watchers ───────────────────────

local function debounced_files_refresh(tabpage, ts)
  close_timer(ts.fs_refresh_timer)
  local timer = vim.uv.new_timer()
  ts.fs_refresh_timer = timer
  timer:start(DEBOUNCE_MS, 0, function()
    pcall(function() timer:close() end)
    if ts.fs_refresh_timer == timer then
      ts.fs_refresh_timer = nil
    end
    vim.schedule(function()
      if not vim.api.nvim_tabpage_is_valid(tabpage) then return end
      M.on_files_changed(tabpage)
    end)
  end)
end

local function stop_file_watchers(ts)
  if not ts.fs_watchers then
    ts.fs_watchers = {}
    return
  end
  for _, w in pairs(ts.fs_watchers) do
    close_handle(w)
  end
  ts.fs_watchers = {}
end

local function collect_expanded(node, dirs)
  if not node or node.type ~= 'directory' then return end
  dirs[node.abs_path] = true
  if node.expanded and node.children then
    for _, child in ipairs(node.children) do
      if child.type == 'directory' and child.expanded then
        collect_expanded(child, dirs)
      end
    end
  end
end

function M.sync_files(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local ts = state.tab_for(tabpage).files

  if not ts.root then
    stop_file_watchers(ts)
    return
  end

  local wanted = {}
  collect_expanded(ts.root, wanted)

  ts.fs_watchers = ts.fs_watchers or {}
  for path, w in pairs(ts.fs_watchers) do
    if not wanted[path] then
      close_handle(w)
      ts.fs_watchers[path] = nil
    end
  end

  for path, _ in pairs(wanted) do
    if not ts.fs_watchers[path] then
      local handle = vim.uv.new_fs_event()
      if handle then
        local ok = pcall(function()
          handle:start(path, {}, function(err)
            if err then return end
            debounced_files_refresh(tabpage, ts)
          end)
        end)
        if ok then
          ts.fs_watchers[path] = handle
        else
          pcall(function() handle:close() end)
        end
      end
    end
  end
end

-- ── .git/index watcher ─────────────────────────────────

local function stop_index_watcher(tab_state)
  if tab_state._index_watcher then
    close_handle(tab_state._index_watcher)
    tab_state._index_watcher = nil
  end
  close_timer(tab_state._index_refresh_timer)
  tab_state._index_refresh_timer = nil
end

local function start_index_watcher(tabpage, tab_state)
  stop_index_watcher(tab_state)

  local root = vim.fs.root(vim.fn.getcwd(), '.git')
  if not root then return end
  local git_dir = root .. '/.git'
  if not vim.uv.fs_stat(git_dir .. '/index') then return end

  local handle = vim.uv.new_fs_event()
  if not handle then return end

  local ok = pcall(function()
    handle:start(git_dir, {}, function(err, filename)
      if err then return end
      if filename ~= 'index' then return end
      close_timer(tab_state._index_refresh_timer)
      local timer = vim.uv.new_timer()
      tab_state._index_refresh_timer = timer
      timer:start(DEBOUNCE_MS, 0, function()
        pcall(function() timer:close() end)
        if tab_state._index_refresh_timer == timer then
          tab_state._index_refresh_timer = nil
        end
        vim.schedule(function()
          if not vim.api.nvim_tabpage_is_valid(tabpage) then return end
          if not state:is_open() then return end
          M.on_index_changed(tabpage)
        end)
      end)
    end)
  end)

  if ok then
    tab_state._index_watcher = handle
  else
    pcall(function() handle:close() end)
  end
end

-- ── public API ─────────────────────────────────────────

function M.start(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local tab_state = state.tab_for(tabpage)
  start_index_watcher(tabpage, tab_state)
end

function M.stop(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local tab_state = state.tab_for(tabpage)
  stop_file_watchers(tab_state.files)
  close_timer(tab_state.files.fs_refresh_timer)
  tab_state.files.fs_refresh_timer = nil
  stop_index_watcher(tab_state)
end

function M.release(ts)
  if not ts then return end
  if ts.files then
    stop_file_watchers(ts.files)
    close_timer(ts.files.fs_refresh_timer)
    ts.files.fs_refresh_timer = nil
  end
  stop_index_watcher(ts)
end

return M
