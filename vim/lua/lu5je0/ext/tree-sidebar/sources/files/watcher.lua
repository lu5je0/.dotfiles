-- fs_event watchers for the file tree.
--
-- Watches every expanded directory in the current root. On change,
-- triggers a debounced refresh through the supplied callback.
local state = require('lu5je0.ext.tree-sidebar.state')

local M = {}

local _watchers = {}
local _refresh_timer = nil
local DEBOUNCE_MS = 300

--- Configured by files/init.lua at module load time.
M.refresh = function() end

local function debounced_refresh()
  if _refresh_timer then _refresh_timer:stop() end
  _refresh_timer = vim.uv.new_timer()
  _refresh_timer:start(DEBOUNCE_MS, 0, function()
    _refresh_timer:close()
    _refresh_timer = nil
    vim.schedule(M.refresh)
  end)
end

local function stop_all()
  for _, w in pairs(_watchers) do
    pcall(function() w:stop() end)
    pcall(function() w:close() end)
  end
  _watchers = {}
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

function M.sync()
  if not state.files.root then
    stop_all()
    return
  end

  local wanted = {}
  collect_expanded(state.files.root, wanted)

  for path, w in pairs(_watchers) do
    if not wanted[path] then
      pcall(function() w:stop() end)
      pcall(function() w:close() end)
      _watchers[path] = nil
    end
  end

  for path, _ in pairs(wanted) do
    if not _watchers[path] then
      local handle = vim.uv.new_fs_event()
      if handle then
        local ok = pcall(function()
          handle:start(path, {}, function(err)
            if not err then debounced_refresh() end
          end)
        end)
        if ok then
          _watchers[path] = handle
        else
          pcall(function() handle:close() end)
        end
      end
    end
  end
end

function M.stop()
  stop_all()
end

return M
