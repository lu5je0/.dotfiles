-- Git status output → section trees (Changes / Staged / Unstaged / Untracked).
local M = {}

local function get_git_root_sync()
  local result = vim.system({ 'git', 'rev-parse', '--show-toplevel' }, { text = true }):wait()
  if result.code == 0 and result.stdout then
    return result.stdout:gsub('%s+$', '')
  end
  return vim.fn.getcwd()
end

local _git_root_cache = {}
function M.git_root()
  local cwd = vim.fn.getcwd()
  if _git_root_cache[cwd] then return _git_root_cache[cwd] end
  _git_root_cache[cwd] = get_git_root_sync()
  return _git_root_cache[cwd]
end

function M.invalidate_root_cache()
  _git_root_cache = {}
end

--- Parse `git status --porcelain=v1 -z --untracked-files=all` into the
--- four sections plus a deduped `changes` section.
function M.parse(stdout)
  local staged, unstaged, untracked, changes = {}, {}, {}, {}
  local seen = {}

  if not stdout or stdout == '' then
    return { staged = staged, unstaged = unstaged, untracked = untracked, changes = changes }
  end

  local entries = vim.split(stdout, '\0', { trimempty = true })
  local i = 1
  while i <= #entries do
    local entry = entries[i]
    if #entry < 4 then i = i + 1; goto continue end
    local xy = entry:sub(1, 2)
    local path = entry:sub(4)
    local x, y = xy:sub(1, 1), xy:sub(2, 2)

    local old_path = nil
    if x == 'R' or x == 'C' then
      i = i + 1
      old_path = entries[i]
    end

    if xy == '!!' then i = i + 1; goto continue end

    if xy == '??' then
      untracked[#untracked + 1] = { path = path, xy = xy, old_path = old_path, x = x, y = y }
    else
      if x ~= ' ' and x ~= '?' then
        staged[#staged + 1] = { path = path, xy = xy, old_path = old_path, x = x, y = y }
      end
      if y ~= ' ' and y ~= '?' then
        unstaged[#unstaged + 1] = { path = path, xy = xy, old_path = old_path, x = x, y = y }
      end
    end

    if not seen[path] then
      seen[path] = true
      changes[#changes + 1] = { path = path, xy = xy, old_path = old_path, x = x, y = y }
    end

    i = i + 1
    ::continue::
  end
  return { staged = staged, unstaged = unstaged, untracked = untracked, changes = changes }
end

--- Build a hierarchical tree of nodes (directories + files) for the
--- given list of file entries within a section.
function M.files_to_tree_nodes(files, expanded_dirs, section_key)
  expanded_dirs = expanded_dirs or {}
  local cwd = M.git_root()
  local root_dirs, root_files = {}, {}

  local function get_or_create_dir(dirs_table, name, abs_prefix)
    for _, d in ipairs(dirs_table) do
      if d.name == name then return d end
    end
    local dir = {
      name = name,
      type = 'directory',
      abs_path = abs_prefix .. '/' .. name,
      expanded = true,
      children = nil,
      _subdirs = {},
      _files = {},
    }
    dirs_table[#dirs_table + 1] = dir
    return dir
  end

  for _, file in ipairs(files) do
    local parts = vim.split(file.path, '/', { trimempty = true })
    if #parts == 1 then
      root_files[#root_files + 1] = {
        name = parts[1],
        type = 'file',
        abs_path = cwd .. '/' .. file.path,
        rel_path = file.path,
        xy = file.xy, x = file.x, y = file.y,
        old_path = file.old_path,
        section = section_key,
      }
    else
      -- Walk down, creating dirs as needed, then drop the file in the deepest one.
      local current_dirs = root_dirs
      local abs_prefix = cwd
      local target_dir
      for di = 1, #parts - 1 do
        target_dir = get_or_create_dir(current_dirs, parts[di], abs_prefix)
        abs_prefix = abs_prefix .. '/' .. parts[di]
        target_dir.abs_path = abs_prefix
        current_dirs = target_dir._subdirs
      end
      target_dir._files[#target_dir._files + 1] = {
        name = parts[#parts],
        type = 'file',
        abs_path = cwd .. '/' .. file.path,
        rel_path = file.path,
        xy = file.xy, x = file.x, y = file.y,
        old_path = file.old_path,
        section = section_key,
      }
    end
  end

  local function finalize(dirs_table, files_table)
    local nodes = {}
    table.sort(dirs_table, function(a, b) return a.name < b.name end)
    table.sort(files_table, function(a, b) return a.name < b.name end)
    for _, dir in ipairs(dirs_table) do
      dir.children = finalize(dir._subdirs, dir._files)
      dir._subdirs, dir._files = nil, nil
      if expanded_dirs[dir.abs_path] ~= nil then
        dir.expanded = expanded_dirs[dir.abs_path]
      end
      nodes[#nodes + 1] = dir
    end
    for _, f in ipairs(files_table) do nodes[#nodes + 1] = f end
    return nodes
  end

  return finalize(root_dirs, root_files)
end

function M.update_sections_from_stdout(tab_state, stdout)
  tab_state.sections = M.parse(stdout)
end

return M
