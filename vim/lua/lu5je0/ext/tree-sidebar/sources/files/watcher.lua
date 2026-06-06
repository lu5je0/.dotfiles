-- fs_event watchers for the file tree.
--
-- Watchers and the debounced refresh timer live in per-tab state
-- (state.files.fs_watchers / state.files.fs_refresh_timer) so each
-- tabpage owns its own resources. Switching tabs no longer tears down
-- and rebuilds another tab's watchers, and a fs_event firing on tab A
-- while the user is on tab B will refresh tab A's data, not B's.
local state = require('lu5je0.ext.tree-sidebar.state')

local M = {}

local DEBOUNCE_MS = 300

--- Configured by files/init.lua at module load time.
--- Receives the tabpage handle whose tree should refresh.
M.refresh = function(_tabpage) end

local function debounced_refresh(tabpage, ts)
  if ts.fs_refresh_timer then
    pcall(function() ts.fs_refresh_timer:stop() end)
    pcall(function() ts.fs_refresh_timer:close() end)
  end
  local timer = vim.uv.new_timer()
  ts.fs_refresh_timer = timer
  timer:start(DEBOUNCE_MS, 0, function()
    pcall(function() timer:close() end)
    if ts.fs_refresh_timer == timer then
      ts.fs_refresh_timer = nil
    end
    vim.schedule(function()
      if not vim.api.nvim_tabpage_is_valid(tabpage) then return end
      M.refresh(tabpage)
    end)
  end)
end

local function stop_all(ts)
  if not ts.fs_watchers then
    ts.fs_watchers = {}
    return
  end
  for _, w in pairs(ts.fs_watchers) do
    pcall(function() w:stop() end)
    pcall(function() w:close() end)
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

--- Re-sync the watcher set for the given tabpage's file tree.
--- Defaults to the current tabpage when called without an argument.
function M.sync(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local ts = state.tab_for(tabpage).files

  if not ts.root then
    stop_all(ts)
    return
  end

  local wanted = {}
  collect_expanded(ts.root, wanted)

  ts.fs_watchers = ts.fs_watchers or {}
  for path, w in pairs(ts.fs_watchers) do
    if not wanted[path] then
      pcall(function() w:stop() end)
      pcall(function() w:close() end)
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
            debounced_refresh(tabpage, ts)
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

--- Stop watchers for the given tabpage (defaults to current).
function M.stop(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local ts = state.tab_for(tabpage).files
  stop_all(ts)
  if ts.fs_refresh_timer then
    pcall(function() ts.fs_refresh_timer:stop() end)
    pcall(function() ts.fs_refresh_timer:close() end)
    ts.fs_refresh_timer = nil
  end
end

return M
