local M = {}

local parse_line = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions').parse_line

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

function M.is_dir_expanded(session, id)
  if not id then return true end
  local entry = session.store[id]
  if not entry then return false end
  return session.expanded_dirs[entry.abs_path] == true
end

function M.is_expanded_at(session, buf, line_nr)
  local line = vim.api.nvim_buf_get_lines(buf, line_nr - 1, line_nr, false)[1]
  if not line then return false end
  local id, name, depth, is_dir = parse_line(line)
  if not id or not is_dir then return false end
  local entry = session.store[id]
  if not entry then return false end
  local shadow_src = session.copy_shadow and session.copy_shadow[id]
  if shadow_src then
    return session.expanded_dirs[shadow_src .. '#' .. id] == true
  end
  local parent_path = session.root_dir
  for i = line_nr - 1, 1, -1 do
    local l = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1]
    if l and l:match('%S') then
      local pid, pname, pdepth, pis_dir = parse_line(l)
      if pdepth < depth then
        if pid and session.store[pid] then
          if session.expanded_dirs[session.store[pid].abs_path] then
            parent_path = session.store[pid].abs_path
          else
            local raw = pis_dir and pname:sub(1, -2) or pname
            parent_path = parent_path .. '/' .. raw
          end
        elseif pis_dir and pname ~= '' then
          parent_path = parent_path .. '/' .. pname:sub(1, -2)
        end
        break
      end
    end
  end
  local raw_name = name:sub(1, -2)
  local current_path = parent_path .. '/' .. raw_name
  return session.expanded_dirs[current_path] == true
    or session.expanded_dirs[entry.abs_path] == true
end

function M.is_displaced(session, buf, line_nr)
  local line = vim.api.nvim_buf_get_lines(buf, line_nr - 1, line_nr, false)[1]
  if not line then return false end
  local id, name, depth, is_dir = parse_line(line)
  if not id or not is_dir then return false end
  local entry = session.store[id]
  if not entry then return false end

  local parent_path = session.root_dir
  for i = line_nr - 1, 1, -1 do
    local l = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1]
    if l and l:match('%S') then
      local pid, pname, pdepth, pis_dir = parse_line(l)
      if pdepth < depth then
        if pid and session.store[pid] then
          if session.expanded_dirs[session.store[pid].abs_path] then
            parent_path = session.store[pid].abs_path
          else
            local raw = pis_dir and pname:sub(1, -2) or pname
            parent_path = parent_path .. '/' .. raw
          end
        elseif pis_dir and pname ~= '' then
          parent_path = parent_path .. '/' .. pname:sub(1, -2)
        end
        break
      end
    end
  end

  local raw_name = name:sub(1, -2)
  local current_path = parent_path .. '/' .. raw_name
  return current_path ~= entry.abs_path
end

return M
