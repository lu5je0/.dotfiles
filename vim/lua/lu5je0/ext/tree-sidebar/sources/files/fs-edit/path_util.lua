local M = {}

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

return M
