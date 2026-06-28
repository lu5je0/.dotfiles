-- Git status integration for the file tree.
--
-- Two responsibilities:
-- 1. Parse `git status --porcelain=v1 -z --ignored` into a path → status map,
--    aggregating directory state by priority for tree decoration.
-- 2. Map status (X,Y) bytes onto a (glyph, hl-group) pair.
local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')
local tree = require('lu5je0.ext.tree-sidebar.sources.files.tree')

local M = {}

local DIR_HL_ORDER = { 'TreeSidebarGitDirty', 'TreeSidebarGitNew', 'TreeSidebarGitStaged' }

--- Convert XY status bytes into the glyph + hl group used in the tree.
function M.status_to_glyph(xy)
  local x, y = xy:sub(1, 1), xy:sub(2, 2)
  if xy == '!!' then
    return config.files.git_glyphs.ignored, 'TreeSidebarGitIgnored'
  elseif xy == '??' then
    return config.files.git_glyphs.untracked, 'TreeSidebarGitNew'
  elseif x == 'D' or y == 'D' then
    return config.files.git_glyphs.deleted, 'TreeSidebarGitDirty'
  elseif x == 'R' then
    return config.files.git_glyphs.renamed, 'TreeSidebarGitDirty'
  elseif x == 'A' then
    return config.files.git_glyphs.staged, 'TreeSidebarGitStaged'
  elseif x ~= ' ' and x ~= '?' then
    return config.files.git_glyphs.staged, 'TreeSidebarGitStaged'
  elseif y == 'M' then
    return config.files.git_glyphs.unstaged, 'TreeSidebarGitDirty'
  end
  return config.files.git_glyphs.unstaged, 'TreeSidebarGitDirty'
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
      local parts = vim.split(path, '/', { trimempty = true })
      local dir = ''
      for pi = 1, #parts - 1 do
        dir = dir .. (pi > 1 and '/' or '') .. parts[pi]
        local bucket = dir_hls[dir]
        if not bucket then
          bucket = {}
          dir_hls[dir] = bucket
        end
        if not bucket[hl] then
          bucket[hl] = { xy = xy, glyph = glyph, hl = hl }
        end
      end
    end
    ::next::
    i = i + 1
  end
  for dir, bucket in pairs(dir_hls) do
    local glyphs = {}
    local winner
    for _, hl in ipairs(DIR_HL_ORDER) do
      local info = bucket[hl]
      if info then
        glyphs[#glyphs + 1] = { info.glyph, info.hl }
        if not winner then winner = info end
      end
    end
    if winner then
      map[dir .. '/'] = { xy = winner.xy, glyph = winner.glyph, hl = winner.hl, glyphs = glyphs }
    end
  end
  return map
end

function M.refresh(callback)
  M.refresh_for(vim.api.nvim_get_current_tabpage(), callback)
end

-- Per-tab variant: writes git status into the captured tabpage's state,
-- so async refreshes triggered on tab A still update tab A even if the
-- user switched tabs while git status was running.
function M.refresh_for(tabpage, callback)
  local tab_files = state.tab_for(tabpage).files
  vim.system({ 'git', 'status', '--porcelain=v1', '-z', '--ignored' }, { text = true }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_tabpage_is_valid(tabpage) then return end
      tab_files.git_status_map = M.build_status_map(result.code == 0 and result.stdout or '')
      if callback then callback() end
    end)
  end)
end

function M.update_from_stdout(tab_files, stdout)
  tab_files.git_status_map = M.build_status_map(stdout or '')
end

function M.is_git_item(item, cwd)
  if not item or not item.node then return false end
  local key
  if item.type == 'file' then
    key = tree.rel_to_cwd(item.node.abs_path, cwd)
  elseif item.type == 'dir' then
    key = tree.rel_to_cwd(item.node.abs_path, cwd) .. '/'
  else
    return false
  end
  return state.files.git_status_map[key] ~= nil
end

return M
