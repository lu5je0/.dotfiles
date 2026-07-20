local config = require('lu5je0.ext.sidebar.config')
local sidebar_render = require('lu5je0.ext.sidebar.render')
local actions_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions')
local pu = require('lu5je0.ext.sidebar.sources.files.fs-edit.path_util')

local M = {}

local parse_line = actions_mod.parse_line
local compute_actions = actions_mod.compute_actions
local check_duplicates = actions_mod.check_duplicates

local hl_ns = vim.api.nvim_create_namespace('sidebar_fyler')
local sign_ns = vim.api.nvim_create_namespace('fs_edit_signs')

M.hl_ns = hl_ns
M.sign_ns = sign_ns

local function get_icon(entry, expanded)
  if entry.type == 'directory' then
    local icons = config.files.folder_icons
    if expanded then
      return icons.open, 'SidebarFolderIcon'
    else
      return icons.closed, 'SidebarFolderIcon'
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
    return config.files.folder_icons.closed, 'SidebarFolderIcon'
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
  local first_line_of_id = {}
  for i, line in ipairs(all_lines) do
    local id, name, depth, is_dir = parse_line(line)
    depths[i] = depth
    parsed[i] = { id = id, name = name, depth = depth, is_dir = is_dir, line = line }
    if id and not first_line_of_id[id] then
      first_line_of_id[id] = i
    end
  end

  -- is_last[i] = no later sibling at the same depth before the next shallower
  -- line. Single stack pass: the nearest previous line with depth <= d is the
  -- stack top after popping deeper entries; an equal-depth top is a previous
  -- sibling and therefore not the last one.
  local is_last = {}
  local sib_stack = {}
  for i = 1, count do
    local d = depths[i]
    while #sib_stack > 0 and depths[sib_stack[#sib_stack]] > d do
      sib_stack[#sib_stack] = nil
    end
    if #sib_stack > 0 and depths[sib_stack[#sib_stack]] == d then
      is_last[sib_stack[#sib_stack]] = false
    end
    is_last[i] = true
    sib_stack[#sib_stack + 1] = i
  end

  local continuation = {}
  local path_stack = { { path = session.root_dir, depth = -1 } }
  for i = 1, count do
    local d = depths[i]
    local p = parsed[i]
    local indent = p.line:match('^(%s*)')
    local line_idx = i - 1

    while #path_stack > 1 and path_stack[#path_stack].depth >= d do
      table.remove(path_stack)
    end
    local parent_path = path_stack[#path_stack].path

    if d >= 1 then
      local guide_parts = {}
      for level = 1, d - 1 do
        if continuation[level] then
          guide_parts[#guide_parts + 1] = { '  ', 'SidebarIndent' }
        else
          guide_parts[#guide_parts + 1] = { '│ ', 'SidebarIndent' }
        end
      end
      guide_parts[#guide_parts + 1] = { is_last[i] and '└ ' or '│ ', 'SidebarIndent' }

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
      local expanded
      local dir_path_for_stack
      if p.is_dir then
        local raw_name = p.name:sub(1, -2)
        local current_path = parent_path .. '/' .. raw_name
        expanded = actions_mod.is_expanded(session, p.id, current_path)
        if first_line_of_id[p.id] and first_line_of_id[p.id] ~= i then
          expanded = false
        end
        dir_path_for_stack = current_path
      end
      icon, icon_hl = get_icon(entry, expanded)
      if p.is_dir then
        table.insert(path_stack, { path = dir_path_for_stack, depth = d })
      elseif entry.type == 'directory' then
        table.insert(path_stack, { path = entry.abs_path, depth = d })
      end
    else
      icon, icon_hl = get_icon_for_name(p.name, p.is_dir)
      if p.is_dir and p.name ~= '' then
        table.insert(path_stack, { path = parent_path .. '/' .. p.name:sub(1, -2), depth = d })
      end
    end
    if icon then
      local indent_len = #indent
      local placeholder = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions').PLACEHOLDER
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
        hl_group = 'SidebarFolderName',
        end_col = #p.line,
        invalidate = true,
      })
      if p.id and session.store[p.id] then
        local sc_key = actions_mod.saved_children_key(session, p.id)
        local is_exp = actions_mod.is_expanded(session, p.id)
        if not is_exp and session.saved_children[sc_key]
          and not (session.saved_children_clean and session.saved_children_clean[sc_key]) then
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

  -- buf_lines: effective lines (saved_children of collapsed dirs spliced in);
  -- line_map: effective index -> 0-based visible row, -1 for spliced entries.
  local buf_lines, line_map = actions_mod.effective_buf_lines_mapped(session, all_lines)

  local act = compute_actions(session, buf_lines)
  local dupes = check_duplicates(session, buf_lines)

  if #act == 0 and #dupes == 0 then
    if vim.bo[buf_nr].modified and not actions_mod.has_pending_changes(session, all_lines) then
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
  local dir_path_to_line = {}
  local i = 0
  for entry in actions_mod.iter_lines(session, buf_lines) do
    i = i + 1
    local lnum = line_map[i]
    local id, name, is_dir = entry.id, entry.name, entry.is_dir
    local new_path = entry.current_path

    if id then
      seen_ids[id] = true
      id_to_line[id] = lnum
      local old_path = session.id_to_path[id] or (session.store[id] and session.store[id].abs_path)
      if old_path and new_path and new_path ~= old_path then
        place(lnum, '▎', 'GitSignsChange')
      end
      if is_dir and new_path then
        dir_path_to_line[new_path] = lnum
      elseif session.store[id] and session.store[id].type == 'directory' then
        dir_path_to_line[session.store[id].abs_path] = lnum
      end
    else
      if name and name ~= '' then
        place(lnum, '▎', 'GitSignsAdd')
        if is_dir and new_path then
          dir_path_to_line[new_path] = lnum
        end
      end
    end
  end

  for i_idx = 1, #buf_lines do
    local lid, _, _, lis_dir = parse_line(buf_lines[i_idx])
    if lis_dir and lid and session.store[lid] then
      local key = actions_mod.saved_children_key(session, lid)
      local exp = actions_mod.is_expanded(session, lid)
      if not exp and session.saved_children[key]
        and not (session.saved_children_clean and session.saved_children_clean[key])
        and line_map[i_idx] and line_map[i_idx] >= 0 then
        place(line_map[i_idx], '▎', 'GitSignsChange')
      end
    end
  end

  local function mark_ancestors(p)
    pu.iter_ancestors(p, session.root_dir, function(parent)
      local lnum = dir_path_to_line[parent]
      if lnum then place(lnum, '▎', 'GitSignsChange') end
    end)
  end
  for _, a in ipairs(act) do
    if a.name ~= 'copy' and a.src then mark_ancestors(a.src) end
    if a.dst then mark_ancestors(a.dst) end
  end

  if session.id_order then
    -- Pre-compute abs paths of collapsed directories whose cache matches disk.
    -- Missing ids underneath these should not get delete markers.
    local clean_collapsed = {}
    local clean = session.saved_children_clean or {}
    for abs, _ in pairs(session.saved_children or {}) do
      if clean[abs] then
        clean_collapsed[abs .. '/'] = true
      end
    end
    local function under_clean_collapsed(path)
      for prefix, _ in pairs(clean_collapsed) do
        if vim.startswith(path, prefix) then return true end
      end
      return false
    end

    for idx, id in ipairs(session.id_order) do
      local path = session.id_to_path[id]
      if path and not seen_ids[id] and not under_clean_collapsed(path) then
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
    local name_lines = {}
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
        name_lines[key] = name_lines[key] or {}
        name_lines[key][#name_lines[key] + 1] = i
        if is_dir then
          table.insert(dupe_stack, { path = parent .. '/' .. raw, depth = depth })
        end
      end
    end
    for key, cnt in pairs(name_count) do
      if cnt > 1 then
        for _, idx in ipairs(name_lines[key]) do
          local lnum = line_map[idx]
          place(lnum, '▎', 'GitSignsChange')
          local bline = buf_lines[idx]
          local _, bname = parse_line(bline)
          local name_start = #bline - #bname
          pcall(vim.api.nvim_buf_set_extmark, buf_nr, sign_ns, lnum, name_start, {
            end_col = #bline,
            hl_group = 'DiagnosticUnderlineError',
            priority = 998,
            invalidate = true,
          })
        end
      end
    end
  end
end

return M
