local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')

local M = {}

local ns_id = vim.api.nvim_create_namespace('tree_sidebar')

-- Buffer operations

function M.set_lines(lines)
  if not state:is_buf_valid() then
    return
  end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

function M.clear_highlights()
  if not state:is_buf_valid() then
    return
  end
  vim.api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)
end

function M.add_highlight(line, hl_group, col_start, col_end)
  if not state:is_buf_valid() then
    return
  end
  vim.api.nvim_buf_add_highlight(state.buf, ns_id, hl_group, line, col_start, col_end)
end

function M.ns_id()
  return ns_id
end

-- Devicons helper

function M.get_file_icon(name)
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  if not ok then
    return '', 'Normal'
  end
  local icon, hl = devicons.get_icon(name, vim.fn.fnamemodify(name, ':e'), { default = true })
  return icon or '', hl or 'Normal'
end

--- Tree rendering engine
---
--- Renders a generic tree structure into lines/items/highlights arrays.
---
--- Each node in the tree must have:
---   - name: string (display name)
---   - type: 'directory' | 'file' (or any non-directory type)
---   - children: list of child nodes (for directories; nil means unloaded)
---   - expanded: boolean (for directories)
---
--- opts:
---   - filter(node) -> bool: whether to show this node (default: show all)
---   - file_suffix(node) -> string|nil, hl_group|nil: extra suffix text & highlight for file nodes
---   - dir_suffix(node) -> string|nil, hl_group|nil: extra suffix text & highlight for dir nodes
---   - get_dir_icon(node) -> icon_str: custom folder icon (default uses config.folder_icons)
---   - item_data(node) -> table: extra fields merged into the item entry
---
--- Returns: lines, items, highlights
function M.render_tree(root_children, opts)
  opts = opts or {}
  local lines = {}
  local items = {}
  local highlights = {}

  local filter = opts.filter or function() return true end
  local file_suffix = opts.file_suffix
  local dir_suffix = opts.dir_suffix
  local item_data = opts.item_data
  local get_dir_icon = opts.get_dir_icon
  local compress_dirs = opts.compress_dirs or false

  local function default_dir_icon(node)
    local has_children = node.children and #node.children > 0
    if not has_children and node.children then
      -- check if any visible children
      for _, c in ipairs(node.children) do
        if filter(c) then
          has_children = true
          break
        end
      end
    else
      has_children = (node.children == nil) or #node.children > 0
    end
    if node.expanded then
      return has_children and config.folder_icons.open or config.folder_icons.empty_open
    else
      return has_children and config.folder_icons.closed or config.folder_icons.empty
    end
  end

  local function walk(children, prefix, depth)
    local visible = {}
    for _, child in ipairs(children) do
      if filter(child) then
        visible[#visible + 1] = child
      end
    end

    local is_root_level = (depth == 0)

    for i, child in ipairs(visible) do
      local child_is_last = (i == #visible)
      local branch = is_root_level and '' or (child_is_last and '└ ' or '│ ')
      local line_prefix = prefix .. branch

      if child.type == 'directory' then
        -- Compress single-child directory chains
        local display_name = child.name
        local display_node = child
        if compress_dirs and child.expanded and child.children and not (child._is_section) then
          while true do
            local visible_children = {}
            for _, c in ipairs(display_node.children or {}) do
              if filter(c) then
                visible_children[#visible_children + 1] = c
              end
            end
            if #visible_children == 1 and visible_children[1].type == 'directory' and visible_children[1].expanded then
              display_node = visible_children[1]
              display_name = display_name .. '/' .. display_node.name
            else
              break
            end
          end
        end

        local icon = get_dir_icon and get_dir_icon(child) or default_dir_icon(display_node)
        local line = line_prefix .. icon .. ' ' .. display_name

        local suffix_text, suffix_hl
        if dir_suffix then
          suffix_text, suffix_hl = dir_suffix(child)
        end
        if suffix_text then
          line = line .. ' ' .. suffix_text
        end

        lines[#lines + 1] = line
        local line_idx = #lines - 1
        local item = { type = 'dir', node = child, line_idx = line_idx }
        if item_data then
          local extra = item_data(child)
          if extra then
            for k, v in pairs(extra) do
              item[k] = v
            end
          end
        end
        items[#items + 1] = item

        -- highlights
        local indent_end = #prefix
        if indent_end > 0 then
          highlights[#highlights + 1] = { line = line_idx, hl = 'TreeSidebarIndent', col_start = 0, col_end = indent_end }
        end
        local branch_end = indent_end + #branch
        highlights[#highlights + 1] = { line = line_idx, hl = 'TreeSidebarIndent', col_start = indent_end, col_end = branch_end }
        highlights[#highlights + 1] = { line = line_idx, hl = 'TreeSidebarFolderIcon', col_start = branch_end, col_end = branch_end + #icon }
        highlights[#highlights + 1] = { line = line_idx, hl = 'TreeSidebarFolderName', col_start = branch_end + #icon + 1, col_end = branch_end + #icon + 1 + #display_name }
        if suffix_text and suffix_hl then
          local suffix_start = #line - #suffix_text
          highlights[#highlights + 1] = { line = line_idx, hl = suffix_hl, col_start = suffix_start, col_end = -1 }
        end

        if display_node.expanded and display_node.children then
          local child_prefix
          if is_root_level then
            child_prefix = ''
          else
            child_prefix = prefix .. (child_is_last and '  ' or '│ ')
          end
          walk(display_node.children, child_prefix, depth + 1)
        end
      else
        local icon, icon_hl = M.get_file_icon(child.name)
        local line = line_prefix .. icon .. ' ' .. child.name

        local suffix_text, suffix_hl
        if file_suffix then
          suffix_text, suffix_hl = file_suffix(child)
        end
        if suffix_text then
          line = line .. '  ' .. suffix_text
        end

        lines[#lines + 1] = line
        local line_idx = #lines - 1
        local item = { type = 'file', node = child, line_idx = line_idx }
        if item_data then
          local extra = item_data(child)
          if extra then
            for k, v in pairs(extra) do
              item[k] = v
            end
          end
        end
        items[#items + 1] = item

        -- highlights
        local indent_end = #prefix
        if indent_end > 0 then
          highlights[#highlights + 1] = { line = line_idx, hl = 'TreeSidebarIndent', col_start = 0, col_end = indent_end }
        end
        local branch_end = indent_end + #branch
        highlights[#highlights + 1] = { line = line_idx, hl = 'TreeSidebarIndent', col_start = indent_end, col_end = branch_end }
        highlights[#highlights + 1] = { line = line_idx, hl = icon_hl, col_start = branch_end, col_end = branch_end + #icon }
        if suffix_text and suffix_hl then
          local suffix_start = #line - #suffix_text
          highlights[#highlights + 1] = { line = line_idx, hl = suffix_hl, col_start = suffix_start, col_end = -1 }
        end
      end
    end
  end

  walk(root_children, '', 0)
  return lines, items, highlights
end

--- Flush lines/items/highlights to the sidebar buffer
function M.flush(lines, highlights)
  M.set_lines(lines)
  M.clear_highlights()
  for _, h in ipairs(highlights) do
    M.add_highlight(h.line, h.hl, h.col_start, h.col_end)
  end
end

function M.open_node(opts)
  if not state:is_open() then
    return
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = opts.get_items()[line]
  if not item then
    return
  end

  if opts.is_expandable(item) then
    if not opts.is_expanded(item) then
      opts.expand(item, line)
      opts.render_fn()
      pcall(vim.api.nvim_win_set_cursor, state.win, { line + 1, 0 })
    elseif opts.on_already_expanded then
      opts.on_already_expanded(item, line)
    end
    return
  end

  if item.type == 'file' and opts.on_file then
    opts.on_file(item, line)
  end
end

function M.close_node(opts)
  if not state:is_open() then
    return
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local items = opts.get_items()
  local item = items[line]
  if not item then
    return
  end

  if opts.is_closeable(item) then
    opts.close(item, line)
    opts.render_fn()
    pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
    return
  end

  for i = line - 1, 1, -1 do
    local parent = items[i]
    if parent then
      if opts.is_boundary and opts.is_boundary(parent) then
        pcall(vim.api.nvim_win_set_cursor, state.win, { i, 0 })
        return
      end
      if opts.is_closeable(parent) then
        opts.close(parent, i)
        opts.render_fn()
        pcall(vim.api.nvim_win_set_cursor, state.win, { i, 0 })
        return
      end
    end
  end
end

return M
