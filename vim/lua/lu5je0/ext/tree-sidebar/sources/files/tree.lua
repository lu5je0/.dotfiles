-- File-tree node operations: scan, ensure children, rebuild, rescan,
-- root building, and the shared dotfile/reveal filter.
local state = require('lu5je0.ext.tree-sidebar.state')

local M = {}

local function is_dotfile(name)
  return name:sub(1, 1) == '.'
end
M.is_dotfile = is_dotfile

--- Strip cwd prefix from an absolute path. Handles cwd == '/' correctly
--- (the naive `:sub(#cwd + 2)` over-strips by one).
function M.rel_to_cwd(abs_path, cwd)
  cwd = cwd or vim.fn.getcwd()
  if cwd == '/' then return abs_path:sub(2) end
  return abs_path:sub(#cwd + 2)
end

function M.scan_dir(path)
  local handle = vim.uv.fs_scandir(path)
  if not handle then return {} end
  local entries = {}
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then break end
    local prefix = path == '/' and '' or path
    local abs_path = prefix .. '/' .. name
    if type == 'link' then
      local stat = vim.uv.fs_stat(abs_path)
      if stat and stat.type == 'directory' then type = 'directory' end
    end
    entries[#entries + 1] = {
      name = name,
      abs_path = abs_path,
      type = type or 'file',
      children = nil,
      expanded = false,
    }
  end
  table.sort(entries, function(a, b)
    if a.type == 'directory' and b.type ~= 'directory' then return true end
    if a.type ~= 'directory' and b.type == 'directory' then return false end
    return a.name < b.name
  end)
  return entries
end

function M.ensure_children(node)
  if node.type == 'directory' and node.children == nil then
    node.children = M.scan_dir(node.abs_path)
  end
end

function M.build_root()
  local cwd = vim.fn.getcwd()
  local root = {
    name = vim.fs.basename(cwd),
    abs_path = cwd,
    type = 'directory',
    children = M.scan_dir(cwd),
    expanded = true,
  }
  state.files.root = root
  return root
end

function M.prepare_tree(node)
  M.ensure_children(node)
  if not node.children then return end
  for _, child in ipairs(node.children) do
    if child.type == 'directory' and child.expanded then
      M.prepare_tree(child)
    end
  end
end

function M.rescan_node(node)
  if node.type ~= 'directory' then return end
  local old_expanded = {}
  for _, child in ipairs(node.children or {}) do
    if child.type == 'directory' and child.expanded then
      old_expanded[child.name] = child
    end
  end
  node.children = M.scan_dir(node.abs_path)
  for _, child in ipairs(node.children) do
    if child.type == 'directory' then
      local old = old_expanded[child.name]
      if old then
        child.expanded = true
        child.children = old.children
        M.rescan_node(child)
      end
    end
  end
end

--- Build a node-visibility filter that hides dotfiles unless either
--- `state.files.hide_dotfiles` is false, or the node lies on the path
--- to `reveal_path`.
function M.make_filter(reveal_path)
  return function(node)
    if not (state.files.hide_dotfiles and is_dotfile(node.name)) then
      return true
    end
    if reveal_path then
      if node.abs_path == reveal_path
        or vim.startswith(reveal_path, node.abs_path .. '/') then
        return true
      end
    end
    return false
  end
end

return M
