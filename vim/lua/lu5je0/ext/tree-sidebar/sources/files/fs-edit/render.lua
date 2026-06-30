local config = require('lu5je0.ext.tree-sidebar.config')
local sidebar_render = require('lu5je0.ext.tree-sidebar.render')
local actions_mod = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.actions')

local M = {}

local parse_line = actions_mod.parse_line
local compute_actions = actions_mod.compute_actions
local check_duplicates = actions_mod.check_duplicates

local hl_ns = vim.api.nvim_create_namespace('tree_sidebar_fyler')
local sign_ns = vim.api.nvim_create_namespace('fs_edit_signs')

M.hl_ns = hl_ns
M.sign_ns = sign_ns

local function get_icon(entry, expanded)
  if entry.type == 'directory' then
    local icons = config.files.folder_icons
    if expanded then
      return icons.open, 'TreeSidebarFolderIcon'
    else
      return icons.closed, 'TreeSidebarFolderIcon'
    end
  else
    local icon, hl = sidebar_render.get_file_icon(entry.name)
    if icon and icon ~= '' then
      return icon, hl
    end
    return nil, nil
  end
end

local function get_icon_for_name(name, is_dir)
  if is_dir then
    return config.files.folder_icons.closed, 'TreeSidebarFolderIcon'
  else
    local clean = name:match('[^/]+$') or name
    local icon, hl = sidebar_render.get_file_icon(clean)
    if icon and icon ~= '' then
      return icon, hl
    end
    return nil, nil
  end
end

local hl_applied = false

function M.refresh_decorations(session, buf_nr)
  if not vim.api.nvim_buf_is_valid(buf_nr) then return end

  if not hl_applied then
    hl_applied = true
    config.apply_highlights()
  end

  vim.api.nvim_buf_clear_namespace(buf_nr, hl_ns, 0, -1)

  local all_lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
  local count = #all_lines
  if count == 0 then return end

  local depths = {}
  local parsed = {}
  for i, line in ipairs(all_lines) do
    local id, name, depth, is_dir = parse_line(line)
    depths[i] = depth
    parsed[i] = { id = id, name = name, depth = depth, is_dir = is_dir, line = line }
  end

  local is_last = {}
  for i = 1, count do
    is_last[i] = true
    for j = i + 1, count do
      if depths[j] < depths[i] then break end
      if depths[j] == depths[i] then is_last[i] = false; break end
    end
  end

  local continuation = {}
  for i = 1, count do
    local d = depths[i]
    local p = parsed[i]
    local indent = p.line:match('^(%s*)')
    local line_idx = i - 1

    if d >= 1 then
      local guide_parts = {}
      for level = 1, d - 1 do
        if continuation[level] then
          guide_parts[#guide_parts + 1] = { '  ', 'TreeSidebarIndent' }
        else
          guide_parts[#guide_parts + 1] = { '│ ', 'TreeSidebarIndent' }
        end
      end
      guide_parts[#guide_parts + 1] = { is_last[i] and '└ ' or '│ ', 'TreeSidebarIndent' }

      vim.api.nvim_buf_set_extmark(buf_nr, hl_ns, line_idx, 0, {
        virt_text = guide_parts,
        virt_text_pos = 'overlay', invalidate = true,
      })
    end

    continuation[d] = is_last[i]
    for k = d + 1, 20 do continuation[k] = nil end

    local icon, icon_hl
    if p.id and session.store[p.id] then
      local entry = session.store[p.id]
      local expanded = p.is_dir and session.expanded_dirs[entry.abs_path]
      icon, icon_hl = get_icon(entry, expanded)
    else
      icon, icon_hl = get_icon_for_name(p.name, p.is_dir)
    end
    if icon then
      local indent_len = #indent
      local placeholder = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.actions').PLACEHOLDER
      local has_placeholder = not p.id and p.line:sub(indent_len + 1, indent_len + #placeholder) == placeholder
      local icon_text = has_placeholder and icon or (icon .. ' ')
      vim.api.nvim_buf_set_extmark(buf_nr, hl_ns, line_idx, indent_len, {
        virt_text = { { icon_text, icon_hl } },
        virt_text_pos = 'inline', invalidate = true,
      })
    end

    if p.is_dir then
      local name_start = #p.line - #p.name
      vim.api.nvim_buf_set_extmark(buf_nr, hl_ns, line_idx, name_start, {
        hl_group = 'TreeSidebarFolderName',
        end_col = #p.line,
        invalidate = true,
      })
      if p.id and session.store[p.id] then
        local entry = session.store[p.id]
        if not session.expanded_dirs[entry.abs_path] and session.saved_children[entry.abs_path] then
          vim.api.nvim_buf_set_extmark(buf_nr, hl_ns, line_idx, 0, {
            virt_text = { { ' [+]', 'GitSignsChange' } },
            virt_text_pos = 'eol', invalidate = true,
          })
        end
      end
    end
  end
end

function M.refresh_diff_signs(session, buf_nr)
  if not vim.api.nvim_buf_is_valid(buf_nr) then return end
  vim.api.nvim_buf_clear_namespace(buf_nr, sign_ns, 0, -1)

  local all_lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
  local line_count = #all_lines

  local buf_lines = {}
  local line_map = {}
  for i, l in ipairs(all_lines) do
    if #l > 0 then
      buf_lines[#buf_lines + 1] = l
      line_map[#buf_lines] = i - 1
    end
  end

  local act = compute_actions(session, buf_lines)
  local dupes = check_duplicates(session, buf_lines)

  if #act == 0 and #dupes == 0 then
    if vim.bo[buf_nr].modified then
      vim.bo[buf_nr].modified = false
    end
    return
  end

  local occupied = {}
  local function place(lnum, text, hl)
    if lnum < 0 or lnum >= line_count then return end
    if occupied[lnum] then return end
    occupied[lnum] = true
    pcall(vim.api.nvim_buf_set_extmark, buf_nr, sign_ns, lnum, 0, {
      sign_text = text,
      sign_hl_group = hl,
      priority = 999,
      invalidate = true,
    })
  end

  local seen_ids = {}
  local id_to_line = {}
  local stack = { { path = session.root_dir, depth = -1 } }
  for i = 1, #buf_lines do
    local id, name, depth, is_dir = parse_line(buf_lines[i])
    local lnum = line_map[i]
    while #stack > 1 and stack[#stack].depth >= depth do
      table.remove(stack)
    end
    local parent_path = stack[#stack].path

    if id then
      seen_ids[id] = true
      id_to_line[id] = lnum
      local raw_name = is_dir and name:sub(1, -2) or name
      local new_path = parent_path .. '/' .. raw_name
      local old_path = session.id_to_path[id] or (session.store[id] and session.store[id].abs_path)
      if old_path and new_path ~= old_path then
        place(lnum, '▎', 'GitSignsChange')
      end
      if is_dir then
        table.insert(stack, { path = new_path, depth = depth })
      elseif session.store[id] and session.store[id].type == 'directory' then
        table.insert(stack, { path = session.store[id].abs_path, depth = depth })
      end
    else
      if name and name ~= '' then
        place(lnum, '▎', 'GitSignsAdd')
      end
      if is_dir then
        local raw = name:sub(1, -2)
        table.insert(stack, { path = parent_path .. '/' .. raw, depth = depth })
      end
    end
  end

  if session.id_order then
    for idx, id in ipairs(session.id_order) do
      if session.id_to_path[id] and not seen_ids[id] then
        local target_line = nil
        for k = idx - 1, 1, -1 do
          if id_to_line[session.id_order[k]] then
            target_line = id_to_line[session.id_order[k]]
            break
          end
        end
        if target_line then
          place(target_line, '▁', 'GitSignsDelete')
        else
          for k = idx + 1, #session.id_order do
            if id_to_line[session.id_order[k]] then
              target_line = id_to_line[session.id_order[k]]
              break
            end
          end
          place(target_line or 0, '▔', 'GitSignsDelete')
        end
      end
    end
  end

  if #dupes > 0 then
    local dupe_stack = { { path = session.root_dir, depth = -1 } }
    local name_count = {}
    for i = 1, #buf_lines do
      local _, name, depth, is_dir = parse_line(buf_lines[i])
      if name ~= '' then
        while #dupe_stack > 1 and dupe_stack[#dupe_stack].depth >= depth do
          table.remove(dupe_stack)
        end
        local parent = dupe_stack[#dupe_stack].path
        local raw = is_dir and name:sub(1, -2) or name
        local key = parent .. '/' .. raw
        name_count[key] = (name_count[key] or 0) + 1
        if name_count[key] > 1 then
          place(line_map[i], '▎', 'DiagnosticError')
        end
        if is_dir then
          table.insert(dupe_stack, { path = parent .. '/' .. raw, depth = depth })
        end
      end
    end
  end
end

return M
