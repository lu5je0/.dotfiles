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

local function add_file_tree_entries(entries, node, opts)
  local prefix = opts.prefix or ''
  local expanded_dirs = opts.expanded_dirs
  local show_status = opts.show_status
  local status_hl_fn = opts.status_hl_fn
  local status_text_fn = opts.status_text_fn
  local status_per_char_hl_fn = opts.status_per_char_hl_fn
  local name_hl_fn = opts.name_hl_fn

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
        add_file_tree_entries(entries, display_node, vim.tbl_extend('force', opts, { prefix = child_prefix }))
      end
    else
      local file = child.node.file
      local status
      if show_status then
        status = status_text_fn and status_text_fn(file) or file.status:sub(1, 1)
      end
      local status_per_char_hl
      if status and status_per_char_hl_fn then
        status_per_char_hl = {}
        for i = 1, #status do
          status_per_char_hl[i] = status_per_char_hl_fn(file, i, status:sub(i, i))
        end
      end
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
        status_hl = status and (status_hl_fn or status_hl)(file.status) or nil,
        status_per_char_hl = status_per_char_hl,
        name_hl = name_hl_fn and name_hl_fn(file) or nil,
        icon = icon,
        icon_hl = icon_hl,
        line = status and (prefix .. branch .. icon .. ' ' .. name .. ' ' .. status)
          or (prefix .. branch .. icon .. ' ' .. name),
      }
    end
  end
end

function M.build_file_tree_entries(commit, opts)
  local root = { dirs = {}, files = {} }
  for file_idx, file in ipairs(commit.files) do
    insert_file_node(root, file_idx, file)
  end

  local entries = {}
  add_file_tree_entries(entries, root, {
    prefix = '',
    expanded_dirs = commit.expanded_dirs or {},
    show_status = not opts or opts.show_status ~= false,
    status_hl_fn = opts and opts.status_hl_fn or nil,
    status_text_fn = opts and opts.status_text_fn or nil,
    status_per_char_hl_fn = opts and opts.status_per_char_hl_fn or nil,
    name_hl_fn = opts and opts.name_hl_fn or nil,
  })
  return entries
end

function M.highlight_tree_entry(buf, line_idx, entry, offset)
  offset = offset or 0
  if offset > 0 then
    vim.api.nvim_buf_add_highlight(buf, ns_id, 'GitTreeLine', line_idx, 0, offset)
  end
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
  if entry.name_hl and icon_start then
    local name_start = offset + icon_start - 1 + #entry.icon + 1
    local name_end
    if entry.status then
      -- " <status>" trailing region, leading space included
      name_end = #entry.line - #entry.status - 1
    else
      name_end = #entry.line
    end
    if name_end > name_start - offset then
      vim.api.nvim_buf_add_highlight(buf, ns_id, entry.name_hl, line_idx, name_start, offset + name_end)
    end
  end
  if entry.status then
    local status_start = #entry.line - #entry.status + 1
    if status_start > 0 then
      if entry.status_per_char_hl then
        for i = 1, #entry.status do
          local hl = entry.status_per_char_hl[i]
          if hl then
            local col = offset + status_start - 1 + (i - 1)
            vim.api.nvim_buf_add_highlight(buf, ns_id, hl, line_idx, col, col + 1)
          end
        end
      else
        vim.api.nvim_buf_add_highlight(buf, ns_id, entry.status_hl, line_idx, offset + status_start - 1, -1)
      end
    end
  end
end

function M.append_tree_entries(lines, items, commit, commit_idx, opts)
  local prefix = opts and opts.prefix or ''
  local indent = #prefix
  local tree_opts = opts and opts.tree_opts or nil
  for _, entry in ipairs(M.build_file_tree_entries(commit, tree_opts)) do
    lines[#lines + 1] = indent > 0 and (prefix .. entry.line) or entry.line
    if entry.type == 'file' then
      items[#items + 1] = { type = 'file', commit_idx = commit_idx, file_idx = entry.file_idx, tree_entry = entry, indent = indent }
    else
      items[#items + 1] = { type = 'dir', commit_idx = commit_idx, dir_path = entry.dir_path, tree_entry = entry, indent = indent }
    end
  end
end

return M
