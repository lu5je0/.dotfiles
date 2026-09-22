local state = require('lu5je0.ext.sidebar.state')

local M = {}

local DEBOUNCE_MS = 300

local function close_handle(handle)
  if not handle then return end
  pcall(function() handle:stop() end)
  pcall(function() handle:close() end)
end

local function is_open(ts)
  return ts.win and vim.api.nvim_win_is_valid(ts.win)
end

function M.refresh(tabpage, force_render)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  if not vim.api.nvim_tabpage_is_valid(tabpage) then return end
  if not is_open(state.tab_for(tabpage)) then return end
  require('lu5je0.ext.sidebar.sources.files').refresh_for(tabpage, force_render)
end

local function debounced_refresh(tabpage, ts)
  close_handle(ts.files.fs_refresh_timer)
  local timer = vim.uv.new_timer()
  ts.files.fs_refresh_timer = timer
  timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
    close_handle(timer)
    if ts.files.fs_refresh_timer ~= timer then return end
    ts.files.fs_refresh_timer = nil
    M.refresh(tabpage)
  end))
end

local function stop_file_watchers(ts)
  for _, handle in pairs(ts.files.fs_watchers) do
    close_handle(handle)
  end
  ts.files.fs_watchers = {}
end

local function collect_expanded(node, dirs)
  if not node or node.type ~= 'directory' then return end
  dirs[node.abs_path] = true
  if node.expanded then
    for _, child in ipairs(node.children or {}) do
      if child.type == 'directory' and child.expanded then
        collect_expanded(child, dirs)
      end
    end
  end
end

function M.sync_files(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local ts = state.tab_for(tabpage)
  local wanted = {}
  if is_open(ts) then collect_expanded(ts.files.root, wanted) end

  for path, handle in pairs(ts.files.fs_watchers) do
    if not wanted[path] then
      close_handle(handle)
      ts.files.fs_watchers[path] = nil
    end
  end

  for path in pairs(wanted) do
    if not ts.files.fs_watchers[path] then
      local handle = vim.uv.new_fs_event()
      if handle then
        local ok, started = pcall(handle.start, handle, path, {}, function(err)
          if err then return end
          debounced_refresh(tabpage, ts)
        end)
        if ok and started then
          ts.files.fs_watchers[path] = handle
        else
          close_handle(handle)
        end
      end
    end
  end
end

local function git_dir(cwd)
  local root = vim.fs.root(cwd, '.git')
  if not root then return end
  local path = root .. '/.git'
  local stat = vim.uv.fs_stat(path)
  if stat and stat.type == 'directory' then return path end
  local ok, lines = pcall(vim.fn.readfile, path, '', 1)
  if not ok then return end
  local target = (lines[1] or ''):match('^gitdir:%s*(.-)%s*$')
  if not target or target == '' then return end
  if not target:match('^[/\\]') and not target:match('^%a:') then
    target = root .. '/' .. target
  end
  return vim.fs.normalize(target)
end

local function sync_index(tabpage, ts)
  local cwd = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tabpage))
  local path = git_dir(cwd)
  if ts._index_path == path and ts._index_watcher then return end
  close_handle(ts._index_watcher)
  ts._index_watcher, ts._index_path = nil, nil
  if not path then return end

  local handle = vim.uv.new_fs_event()
  if not handle then return end
  local ok, started = pcall(handle.start, handle, path, {}, function(err, filename)
    if err then return end
    if filename and filename ~= 'index' and filename ~= 'HEAD' and filename ~= 'packed-refs' then return end
    debounced_refresh(tabpage, ts)
  end)
  if ok and started then
    ts._index_watcher, ts._index_path = handle, path
  else
    close_handle(handle)
  end
end

function M.start(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local ts = state.tab_for(tabpage)
  if not is_open(ts) then return end
  M.sync_files(tabpage)
  sync_index(tabpage, ts)
end

function M.stop(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local ts = state.tab_for(tabpage)
  M.release(ts)
  require('lu5je0.ext.sidebar.git_status').release(ts)
end

function M.release(ts)
  if not ts then return end
  stop_file_watchers(ts)
  close_handle(ts.files.fs_refresh_timer)
  ts.files.fs_refresh_timer = nil
  close_handle(ts._index_watcher)
  ts._index_watcher, ts._index_path = nil, nil
end

return M
