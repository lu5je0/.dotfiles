-- Git status integration for the file tree.
--
-- Two responsibilities:
-- 1. Parse porcelain-v1 status output into a path → status map, aggregating
--    directory state by priority for tree decoration.
-- 2. Map status (X,Y) bytes onto a (glyph, hl-group) pair.
local state = require('lu5je0.ext.sidebar.state')
local config = require('lu5je0.ext.sidebar.config')
local tree = require('lu5je0.ext.sidebar.sources.files.tree')

local M = {}

local DIR_HL_ORDER = { 'SidebarGitConflict', 'SidebarGitDirty', 'SidebarGitNew', 'SidebarGitStaged' }
local UNMERGED = { DD = true, AU = true, UD = true, UA = true, DU = true, AA = true, UU = true }

--- Convert XY status bytes into the glyph + hl group used in the tree.
function M.status_to_glyph(xy)
  local x, y = xy:sub(1, 1), xy:sub(2, 2)
  if xy == '!!' then
    return config.files.git_glyphs.ignored, 'SidebarGitIgnored'
  elseif xy == '??' then
    return config.files.git_glyphs.untracked, 'SidebarGitNew'
  elseif UNMERGED[xy] then
    return config.files.git_glyphs.unmerged, 'SidebarGitConflict'
  elseif x == 'D' or y == 'D' then
    return config.files.git_glyphs.deleted, 'SidebarGitDirty'
  elseif x == 'R' then
    return config.files.git_glyphs.renamed, 'SidebarGitDirty'
  elseif x == 'A' then
    return config.files.git_glyphs.staged, 'SidebarGitStaged'
  elseif x ~= ' ' and x ~= '?' then
    return config.files.git_glyphs.staged, 'SidebarGitStaged'
  elseif y == 'M' then
    return config.files.git_glyphs.unstaged, 'SidebarGitDirty'
  end
  return config.files.git_glyphs.unstaged, 'SidebarGitDirty'
end

function M.build_status_map(stdout)
  local map = {}
  if not stdout or stdout == '' then return map end
  local dir_hls = {}
  local entries = vim.split(stdout, '\0', { trimempty = true })
  local i = 1
  while i <= #entries do
    local entry = entries[i]
    if #entry >= 4 then
      local xy = entry:sub(1, 2)
      local path = entry:sub(4)
      local x = xy:sub(1, 1)
      if x == 'R' or x == 'C' then i = i + 1 end
      local glyph, hl = M.status_to_glyph(xy)
      map[path] = { xy = xy, glyph = glyph, hl = hl }
      if xy == '!!' then goto next end
      -- Summaries prioritize pending work even when a file's icon favors the index.
      local dir_hl = hl
      if not UNMERGED[xy] and xy ~= '??' then
        dir_hl = xy:sub(2, 2) ~= ' ' and 'SidebarGitDirty' or 'SidebarGitStaged'
      end
      local dir_glyph = UNMERGED[xy] and config.files.git_directory_glyphs.unmerged
        or config.files.git_directory_glyphs.changed
      local parts = vim.split(path, '/', { trimempty = true })
      local dir = ''
      for pi = 1, #parts - 1 do
        dir = dir .. (pi > 1 and '/' or '') .. parts[pi]
        local bucket = dir_hls[dir]
        if not bucket then
          bucket = {}
          dir_hls[dir] = bucket
        end
        if not bucket[dir_hl] then
          bucket[dir_hl] = { xy = xy, glyph = dir_glyph, hl = dir_hl }
        end
      end
    end
    ::next::
    i = i + 1
  end
  for dir, bucket in pairs(dir_hls) do
    for _, hl in ipairs(DIR_HL_ORDER) do
      local info = bucket[hl]
      if info then
        map[dir .. '/'] = info
        break
      end
    end
  end
  return map
end

function M.update_from_stdout(tab_files, stdout)
  tab_files.git_status_map = M.build_status_map(stdout or '')
end

function M.status_for_node(node, cwd)
  local path = tree.rel_to_cwd(node.abs_path, state.files.git_root or cwd)
  local map = state.files.git_status_map
  local status = map[path .. (node.type == 'directory' and '/' or '')]
  if status then return status end
  local parent = path:match('^(.*)/[^/]+$')
  while parent do
    status = map[parent .. '/']
    if status and status.xy == '!!' then return status end
    parent = parent:match('^(.*)/[^/]+$')
  end
end

function M.is_git_item(item, cwd)
  if not item or not item.node or (item.type ~= 'file' and item.type ~= 'dir') then return false end
  return M.status_for_node(item.node, cwd) ~= nil
end

return M
