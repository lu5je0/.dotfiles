local M = {}

local actions = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions')
local parse_line = actions.parse_line

function M.strip_slash(p)
  if not p then return p end
  if vim.endswith(p, '/') then return p:sub(1, -2) end
  return p
end

function M.rel(root, p)
  if not p then return p end
  if vim.startswith(p, root .. '/') then
    return p:sub(#root + 2)
  end
  return p
end

function M.inside(child, parent)
  if not child or not parent or parent == '' then return false end
  child = M.strip_slash(child)
  parent = M.strip_slash(parent)
  return child == parent or vim.startswith(child, parent .. '/')
end

-- Iterate strict ancestors of p, stopping before reaching root_dir.
-- Useful: never visits root_dir itself; stops at filesystem root if root_dir is above p.
function M.iter_ancestors(p, root_dir, fn)
  if not p or p == '' then return end
  p = M.strip_slash(p)
  for parent in vim.fs.parents(p) do
    if parent == root_dir then return end
    fn(parent)
  end
end

-- Effective buffer path of the id'd entry at line_nr, respecting any renames
-- above it. Walks up through every shallower line: no-id dirs contribute a
-- path segment each (they may nest several levels), an id'd line anchors the
-- walk via recursion. Returns nil when the line has no id.
local function current_path_in_lines(session, lines, line_nr)
  local line = lines[line_nr]
  if not line then return nil end
  local id, name, depth, is_dir = parse_line(line)
  if not id then return nil end
  local segments = {}
  local parent_path
  local cur_depth = depth
  for i = line_nr - 1, 1, -1 do
    local l = lines[i]
    if l and l:match('%S') then
      local pid, pname, pdepth, pis_dir = parse_line(l)
      if pdepth < cur_depth then
        if pid and session.store[pid] then
          local pcur = current_path_in_lines(session, lines, i)
          if pcur then
            parent_path = pcur
          elseif pis_dir then
            parent_path = session.store[pid].abs_path
          end
          break
        elseif pis_dir and pname ~= '' then
          table.insert(segments, 1, pname:sub(1, -2))
          cur_depth = pdepth
        else
          break
        end
      end
    end
  end
  parent_path = parent_path or session.root_dir
  for _, seg in ipairs(segments) do
    parent_path = parent_path .. '/' .. seg
  end
  local raw_name = is_dir and name:sub(1, -2) or name
  return parent_path .. '/' .. raw_name
end

function M.current_path(session, buf, line_nr)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, line_nr, false)
  return current_path_in_lines(session, lines, line_nr)
end

function M.is_expanded_at(session, buf, line_nr)
  local line = vim.api.nvim_buf_get_lines(buf, line_nr - 1, line_nr, false)[1]
  if not line then return false end
  local id, _, _, is_dir = parse_line(line)
  if not id or not is_dir then return false end
  if not session.store[id] then return false end
  if session.copy_shadow and session.copy_shadow[id] then
    return actions.is_expanded(session, id)
  end
  local current_path = M.current_path(session, buf, line_nr)
  if not current_path then return false end
  return actions.is_expanded(session, id, current_path)
end

function M.is_displaced(session, buf, line_nr)
  local line = vim.api.nvim_buf_get_lines(buf, line_nr - 1, line_nr, false)[1]
  if not line then return false end
  local id, _, _, is_dir = parse_line(line)
  if not id or not is_dir then return false end
  local entry = session.store[id]
  if not entry then return false end
  local current_path = M.current_path(session, buf, line_nr)
  if not current_path then return false end
  return current_path ~= entry.abs_path
end

return M
