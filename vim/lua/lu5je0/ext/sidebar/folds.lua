local M = {}

local actions = {
  { 'zo', 'open', 'Open fold' },
  { 'zc', 'close', 'Close fold' },
  { 'zO', 'open_recursive', 'Open folds recursively' },
  { 'zC', 'close_subtree', 'Close fold recursively' },
  { 'zR', 'expand_all', 'Expand all folds in scope' },
  { 'zM', 'collapse_all', 'Collapse all folds' },
}

function M.keymaps(handlers)
  local maps = {}
  if not handlers then return maps end
  for _, action in ipairs(actions) do
    local lhs, name, desc = unpack(action)
    if handlers[name] then
      maps[#maps + 1] = { lhs, handlers[name], desc = desc }
    end
  end
  return maps
end

function M.set_subtree(nodes, expanded, on_dir)
  for _, node in ipairs(nodes or {}) do
    if node.type == 'directory' then
      node.expanded = expanded
      if on_dir then on_dir(node, expanded) end
      M.set_subtree(node.children, expanded, on_dir)
    end
  end
end

return M
