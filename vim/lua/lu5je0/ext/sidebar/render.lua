-- Tree rendering engine: converts a tree of nodes into
-- lines / items / highlights / virt_texts.
--
-- This module is pure: it does not touch state, buffers or windows.
-- For buffer flushing and cursor-aware open/close/restore glue see view.lua.
-- For backward compatibility this module re-exports view.flush /
-- open_node / close_node / restore_cursor / ns_id / set_lines /
-- clear_highlights / add_highlight, since several call sites still go
-- through `render.X`.
local config = require('lu5je0.ext.sidebar.config')
local view = require('lu5je0.ext.sidebar.view')

local M = {}

-- ── view re-exports (backward-compat) ───────────────────

M.ns_id = view.ns_id
M.set_lines = view.set_lines
M.clear_highlights = view.clear_highlights
M.add_highlight = view.add_highlight
M.flush = view.flush
M.open_node = view.open_node
M.close_node = view.close_node
M.restore_cursor = view.restore_cursor

-- ── devicons ────────────────────────────────────────────

local _devicons, _devicons_loaded = nil, false

function M.get_file_icon(name)
  if not _devicons_loaded then
    _devicons_loaded = true
    local ok, mod = pcall(require, 'nvim-web-devicons')
    if ok then _devicons = mod end
  end
  if not _devicons then return '', 'Normal' end
  local icon, hl = _devicons.get_icon(name, vim.fn.fnamemodify(name, ':e'), { default = true })
  return icon or '', hl or 'Normal'
end

-- ── tree render engine ──────────────────────────────────
--
-- Each node must have:
--   - name: string
--   - type: 'directory' | 'file' (or any non-directory)
--   - children: list (for directories; nil = unloaded)
--   - expanded: boolean (for directories)
--
-- opts:
--   filter(node)        -> bool
--   file_suffix(node)   -> text, hl
--   dir_suffix(node)    -> text, hl
--   get_dir_icon(node)  -> icon
--   get_file_icon(node) -> icon, hl
--   node_hl(node)       -> hl-group | nil  (overrides icon+name hl, inherited downward)
--   item_data(node)     -> table (merged into the produced item entry)
--   compress_dirs       -> bool
--   flat_depth          -> int, depth at which children skip the branch prefix
--
-- Returns: lines, items, highlights, virt_texts
--
-- Indexing convention (important):
--   * `lines`, `items`, `highlights`, `virt_texts` are all 1-based Lua arrays.
--   * Inside each item / highlight / virt_text entry, the `line_idx` /
--     `line` field is 0-based to match Neovim's buffer + extmark API.
--   * To get the text of an item: `lines[item.line_idx + 1]`.
--   * The 1-based array index of an item also happens to be its target
--     row for `nvim_win_set_cursor({ i, 0 })` (cursor rows are 1-based).
function M.render_tree(root_children, opts)
  opts = opts or {}
  local lines, items, highlights, virt_texts = {}, {}, {}, {}

  local filter = opts.filter or function() return true end
  local file_suffix = opts.file_suffix
  local dir_suffix = opts.dir_suffix
  local item_data = opts.item_data
  local get_dir_icon = opts.get_dir_icon
  local get_file_icon_fn = opts.get_file_icon
  local node_hl = opts.node_hl
  local compress_dirs = opts.compress_dirs or false
  local flat_depth = opts.flat_depth or 0
  local simple_indent = opts.simple_indent or false

  local function default_dir_icon(node)
    if node.is_symlink then
      if node.expanded then
        return config.files.folder_icons.symlink_open
      end
      return config.files.folder_icons.symlink
    end
    local has_children = node.children and #node.children > 0
    if not has_children and node.children then
      for _, c in ipairs(node.children) do
        if filter(c) then has_children = true; break end
      end
    else
      has_children = (node.children == nil) or #node.children > 0
    end
    if node.expanded then
      return has_children and config.files.folder_icons.open or config.files.folder_icons.empty_open
    else
      return has_children and config.files.folder_icons.closed or config.files.folder_icons.empty
    end
  end

  local function add_item(node, line_idx, kind)
    local item = { type = kind, node = node, line_idx = line_idx }
    if item_data then
      local extra = item_data(node)
      if extra then
        for k, v in pairs(extra) do item[k] = v end
      end
    end
    items[#items + 1] = item
  end

  local function add_indent_hls(line_idx, indent_end, branch_end)
    if indent_end > 0 then
      highlights[#highlights + 1] = { line = line_idx, hl = 'SidebarIndent', col_start = 0, col_end = indent_end }
    end
    highlights[#highlights + 1] = { line = line_idx, hl = 'SidebarIndent', col_start = indent_end, col_end = branch_end }
  end

  local function add_suffix(line_idx, text, hl)
    if not text then return end
    local vt = type(hl) == 'table' and hl or { { text, hl } }
    virt_texts[#virt_texts + 1] = { line = line_idx, virt_text = vt }
  end

  local function compress_chain(child)
    -- Returns final display_node and joined display_name.
    local display_name, display_node = child.name, child
    if not (compress_dirs and child.expanded and child.children and not child._is_section) then
      return display_name, display_node
    end
    while true do
      local visible_dir = nil
      local found_one = false
      local multiple = false
      for _, c in ipairs(display_node.children or {}) do
        if filter(c) then
          if found_one then multiple = true; break end
          found_one = true
          if c.type == 'directory' and c.expanded then
            visible_dir = c
          else
            visible_dir = nil
          end
        end
      end
      if multiple or not visible_dir then break end
      display_node = visible_dir
      display_name = display_name .. '/' .. visible_dir.name
    end
    return display_name, display_node
  end

  local function walk(children, prefix, depth, inherited_hl)
    local visible = {}
    for _, child in ipairs(children) do
      if filter(child) then visible[#visible + 1] = child end
    end

    local is_root_level = (depth <= flat_depth)

    for i, child in ipairs(visible) do
      local child_is_last = (i == #visible)
      local branch
      if simple_indent then
        if is_root_level then
          branch = child.type == 'directory' and '' or '  '
        elseif child.type == 'directory' then
          branch = ''
        else
          branch = child_is_last and '└ ' or '├ '
        end
      else
        branch = is_root_level and '' or (child_is_last and '└ ' or '│ ')
      end
      local line_prefix = prefix .. branch
      local indent_end = #prefix
      local branch_end = indent_end + #branch

      if child.type == 'directory' then
        local display_name, display_node = compress_chain(child)
        local icon = get_dir_icon and get_dir_icon(child) or default_dir_icon(display_node)
        local line = line_prefix .. icon .. ' ' .. display_name

        lines[#lines + 1] = line
        local line_idx = #lines - 1
        add_item(child, line_idx, 'dir')

        if dir_suffix then
          add_suffix(line_idx, dir_suffix(child))
        end

        add_indent_hls(line_idx, indent_end, branch_end)
        local effective_hl = (node_hl and node_hl(child)) or inherited_hl
        local folder_icon_hl = effective_hl or 'SidebarFolderIcon'
        local folder_name_hl = effective_hl or 'SidebarFolderName'
        highlights[#highlights + 1] = { line = line_idx, hl = folder_icon_hl, col_start = branch_end, col_end = branch_end + #icon }
        highlights[#highlights + 1] = { line = line_idx, hl = folder_name_hl, col_start = branch_end + #icon + 1, col_end = branch_end + #icon + 1 + #display_name }

        if display_node.expanded and display_node.children then
          local child_prefix
          if simple_indent then
            child_prefix = prefix .. '  '
          elseif is_root_level then
            child_prefix = ''
          else
            child_prefix = prefix .. (child_is_last and '  ' or '│ ')
          end
          walk(display_node.children, child_prefix, depth + 1, effective_hl)
        end
      else
        local icon, icon_hl
        if get_file_icon_fn then
          icon, icon_hl = get_file_icon_fn(child)
        else
          icon, icon_hl = M.get_file_icon(child.name)
        end
        local line = line_prefix .. icon .. ' ' .. child.name

        lines[#lines + 1] = line
        local line_idx = #lines - 1
        add_item(child, line_idx, 'file')

        if file_suffix then
          add_suffix(line_idx, file_suffix(child))
        end

        add_indent_hls(line_idx, indent_end, branch_end)
        local effective_hl = (node_hl and node_hl(child)) or inherited_hl
        local final_icon_hl = effective_hl or icon_hl
        highlights[#highlights + 1] = { line = line_idx, hl = final_icon_hl, col_start = branch_end, col_end = branch_end + #icon }
        if effective_hl then
          highlights[#highlights + 1] = { line = line_idx, hl = effective_hl, col_start = branch_end + #icon + 1, col_end = branch_end + #icon + 1 + #child.name }
        end
      end
    end
  end

  walk(root_children, '', 0, nil)
  return lines, items, highlights, virt_texts
end

return M
