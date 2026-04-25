local M = {}

local ns_id = vim.api.nvim_create_namespace('git_common')

vim.api.nvim_set_hl(0, 'GitTreeLine', { link = 'Directory', default = true })
vim.api.nvim_set_hl(0, 'GitFolderIcon', { link = 'Directory', default = true })
vim.api.nvim_set_hl(0, 'GitFolderName', { fg = '#e5c07b', default = true })

function M.set_buffer_lines(buf, lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function status_hl(status)
  local kind = status:sub(1, 1)
  if kind == 'A' then
    return 'DiffAdd'
  elseif kind == 'D' then
    return 'DiffDelete'
  elseif kind == 'R' or kind == 'C' or kind == '?' then
    return 'Special'
  end
  return 'DiffChange'
end

local function get_file_icon(path)
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  if not ok then
    return '', 'Normal'
  end
  local icon, hl = devicons.get_icon(path, vim.fn.fnamemodify(path, ':e'), { default = true })
  return icon or '', hl or 'Normal'
end

local function split_path(path)
  return vim.split(path or '', '/', { plain = true, trimempty = true })
end

local function insert_file_node(root, file_idx, file)
  local parts = split_path(file.path)
  if #parts == 0 then
    return
  end

  local node = root
  local dir_parts = {}
  for i = 1, #parts - 1 do
    local name = parts[i]
    dir_parts[#dir_parts + 1] = name
    node.dirs[name] = node.dirs[name] or {
      name = name,
      path = table.concat(dir_parts, '/'),
      dirs = {},
      files = {},
    }
    node = node.dirs[name]
  end

  node.files[#node.files + 1] = {
    name = parts[#parts],
    file_idx = file_idx,
    file = file,
  }
end

local function sorted_values(tbl)
  local values = {}
  for _, value in pairs(tbl) do
    values[#values + 1] = value
  end
  table.sort(values, function(a, b)
    return a.name < b.name
  end)
  return values
end

local function node_has_children(node)
  return #node.files > 0 or next(node.dirs) ~= nil
end

local function only_dir_child(node)
  local only = nil
  for _, dir in pairs(node.dirs) do
    if only then
      return nil
    end
    only = dir
  end
  return only
end

local function compressed_dir_node(node, expanded_dirs)
  local current = node
  local parent_dir = vim.fn.fnamemodify(node.path, ':h')
  local names = { current.name }
  while expanded_dirs[current.path] == true and #current.files == 0 do
    local child = only_dir_child(current)
    if not child then
      break
    end
    current = child
    names[#names + 1] = current.name
  end
  return current, table.concat(names, '/'), parent_dir
end

local function add_file_tree_entries(entries, node, prefix, expanded_dirs)
  local children = {}
  for _, dir in ipairs(sorted_values(node.dirs)) do
    children[#children + 1] = { type = 'dir', node = dir }
  end
  table.sort(node.files, function(a, b)
    return a.name < b.name
  end)
  for _, file_node in ipairs(node.files) do
    children[#children + 1] = { type = 'file', node = file_node }
  end

  for idx, child in ipairs(children) do
    local is_last = idx == #children
    local branch = is_last and '└ ' or '│ '
    if child.type == 'dir' then
      local display_node, display_name, parent_dir = compressed_dir_node(child.node, expanded_dirs)
      local has_children = node_has_children(display_node)
      local expanded = expanded_dirs[display_node.path] == true
      local icon = expanded and '' or ''
      entries[#entries + 1] = {
        type = 'dir',
        dir_path = display_node.path,
        parent_dir = parent_dir,
        has_children = has_children,
        expanded = expanded,
        icon = icon,
        line = prefix .. branch .. icon .. ' ' .. display_name,
      }
      if expanded then
        local child_prefix = prefix .. (is_last and '  ' or '│ ')
        add_file_tree_entries(entries, display_node, child_prefix, expanded_dirs)
      end
    else
      local file = child.node.file
      local status = file.status:sub(1, 1)
      local icon, icon_hl = get_file_icon(file.path)
      local name = child.node.name
      if file.old_path then
        name = vim.fn.fnamemodify(file.old_path, ':t') .. ' -> ' .. name
      end
      entries[#entries + 1] = {
        type = 'file',
        file_idx = child.node.file_idx,
        parent_dir = vim.fn.fnamemodify(file.path, ':h'),
        status = status,
        status_hl = status_hl(file.status),
        icon = icon,
        icon_hl = icon_hl,
        line = prefix .. branch .. icon .. ' ' .. name .. ' ' .. status,
      }
    end
  end
end

function M.build_file_tree_entries(commit)
  local root = { dirs = {}, files = {} }
  for file_idx, file in ipairs(commit.files) do
    insert_file_node(root, file_idx, file)
  end

  local entries = {}
  add_file_tree_entries(entries, root, '', commit.expanded_dirs or {})
  return entries
end

function M.highlight_tree_entry(buf, line_idx, entry, offset)
  offset = offset or 0
  local icon_start = entry.line:find(entry.icon, 1, true)
  if icon_start and icon_start > 1 then
    vim.api.nvim_buf_add_highlight(buf, ns_id, 'GitTreeLine', line_idx, offset, offset + icon_start - 1)
  end

  if entry.type == 'dir' then
    if icon_start then
      vim.api.nvim_buf_add_highlight(buf, ns_id, 'GitFolderIcon', line_idx, offset + icon_start - 1, offset + icon_start - 1 + #entry.icon)
      vim.api.nvim_buf_add_highlight(buf, ns_id, 'GitFolderName', line_idx, offset + icon_start - 1 + #entry.icon + 1, -1)
    end
    return
  end

  if icon_start then
    vim.api.nvim_buf_add_highlight(buf, ns_id, entry.icon_hl, line_idx, offset + icon_start - 1, offset + icon_start - 1 + #entry.icon)
  end
  local status_start = #entry.line - #entry.status + 1
  if status_start > 0 then
    vim.api.nvim_buf_add_highlight(buf, ns_id, entry.status_hl, line_idx, offset + status_start - 1, -1)
  end
end

return M
