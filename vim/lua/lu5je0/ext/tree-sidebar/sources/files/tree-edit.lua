local tree = require('lu5je0.ext.tree-sidebar.sources.files.tree')
local win_mod = require('lu5je0.ext.tree-sidebar.window')
local config = require('lu5je0.ext.tree-sidebar.config')
local render = require('lu5je0.ext.tree-sidebar.render')

local M = {}

local sessions = {}

local function find_sidebar_node(root, abs_path)
  if root.abs_path == abs_path then return root end
  if not root.children then return nil end
  for _, child in ipairs(root.children) do
    if child.abs_path == abs_path then return child end
    if child.type == 'directory' and vim.startswith(abs_path, child.abs_path .. '/') then
      local found = find_sidebar_node(child, abs_path)
      if found then return found end
    end
  end
end

local function seed_expanded(session, node)
  if not node or not node.children then return end
  for _, child in ipairs(node.children) do
    if child.type == 'directory' and child.expanded then
      session.expanded_dirs[child.abs_path] = true
      seed_expanded(session, child)
    end
  end
end

local function register_entry(session, abs_path, name, entry_type)
  for id, entry in pairs(session.store) do
    if entry.abs_path == abs_path then return id end
  end
  local id = session.next_id
  session.next_id = id + 1
  session.store[id] = { name = name, abs_path = abs_path, type = entry_type }
  session.id_to_path[id] = abs_path
  return id
end

local function get_icon(entry, expanded)
  if entry.type == 'directory' then
    local icons = config.files.folder_icons
    if expanded then
      return icons.open, 'TreeSidebarFolderIcon'
    else
      return icons.closed, 'TreeSidebarFolderIcon'
    end
  else
    local icon, hl = render.get_file_icon(entry.name)
    if icon and icon ~= '' then
      return icon, hl
    end
    return nil, nil
  end
end

-- Parse a buffer line. Returns id (or nil), name, depth, is_dir.
local function parse_line(line)
  local indent = line:match('^(%s*)')
  local depth = #indent / 2
  local rest = line:sub(#indent + 1)
  local id_str = rest:match('^/(%d+) ')
  local id = id_str and tonumber(id_str) or nil
  local name
  if id then
    name = rest:match('^/%d+ (.+)$')
  else
    name = rest
  end
  if not name then name = '' end
  local is_dir = vim.endswith(name, '/')
  return id, name, depth, is_dir
end

local function get_icon_for_name(name, is_dir)
  if is_dir then
    return config.files.folder_icons.closed, 'TreeSidebarFolderIcon'
  else
    local clean = name:match('[^/]+$') or name
    local icon, hl = render.get_file_icon(clean)
    if icon and icon ~= '' then
      return icon, hl
    end
    return nil, nil
  end
end

local hl_ns = vim.api.nvim_create_namespace('tree_sidebar_fyler')
local sign_ns = vim.api.nvim_create_namespace('tree_edit_signs')

local compute_actions
local check_duplicates

local function refresh_diff_signs(session, buf_nr)
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

  local actions = compute_actions(session, buf_lines)
  local dupes = check_duplicates(session, buf_lines)

  if #actions == 0 and #dupes == 0 then
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
    })
  end

  -- per-line sign via path comparison
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

  -- mark duplicate name lines
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

local hl_applied = false

local function refresh_decorations(session, buf_nr)
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
        virt_text_pos = 'overlay',
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
      vim.api.nvim_buf_set_extmark(buf_nr, hl_ns, line_idx, #indent, {
        virt_text = { { icon .. ' ', icon_hl } },
        virt_text_pos = 'inline',
      })
    end

    if p.is_dir then
      local name_start = #p.line - #p.name
      vim.api.nvim_buf_set_extmark(buf_nr, hl_ns, line_idx, name_start, {
        hl_group = 'TreeSidebarFolderName',
        end_col = #p.line,
      })
    end
  end
end

local function render_to_lines(session)
  local lines = {}
  local id_order = {}

  local function walk(dir_path, depth)
    local entries = tree.scan_dir(dir_path)
    for _, entry in ipairs(entries) do
      local id = register_entry(session, entry.abs_path, entry.name, entry.type)
      local indent = string.rep('  ', depth)
      local name = entry.name
      local expanded = entry.type == 'directory' and session.expanded_dirs[entry.abs_path]
      if entry.type == 'directory' then
        name = name .. '/'
      end
      lines[#lines + 1] = string.format('%s/%d %s', indent, id, name)
      id_order[#id_order + 1] = id
      if expanded then
        walk(entry.abs_path, depth + 1)
      end
    end
  end

  walk(session.root_dir, 0)
  session.id_order = id_order
  return lines
end

local function render_children(session, dir_path, depth)
  local lines = {}
  local new_ids = {}

  local function walk(path, d)
    local entries = tree.scan_dir(path)
    for _, entry in ipairs(entries) do
      local id = register_entry(session, entry.abs_path, entry.name, entry.type)
      session.id_to_path[id] = entry.abs_path
      local indent = string.rep('  ', d)
      local name = entry.name
      local expanded = entry.type == 'directory' and session.expanded_dirs[entry.abs_path]
      if entry.type == 'directory' then
        name = name .. '/'
      end
      lines[#lines + 1] = string.format('%s/%d %s', indent, id, name)
      new_ids[#new_ids + 1] = id
      if expanded then
        walk(entry.abs_path, d + 1)
      end
    end
  end

  walk(dir_path, depth)
  return lines, new_ids
end

local function remove_children_lines(session, buf, line_nr, depth)
  local total = vim.api.nvim_buf_line_count(buf)
  local end_line = line_nr + 1
  while end_line <= total do
    local l = vim.api.nvim_buf_get_lines(buf, end_line - 1, end_line, false)[1]
    local _, _, d = parse_line(l)
    if d <= depth then break end
    local cid = l:match('/(%d+) ')
    if cid then
      session.id_to_path[tonumber(cid)] = nil
    end
    end_line = end_line + 1
  end
  if end_line > line_nr + 1 then
    vim.api.nvim_buf_set_lines(buf, line_nr, end_line - 1, false, {})
  end
end

local function on_enter(session)
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(session.buf, line_nr - 1, line_nr, false)[1]
  local id, _, depth, is_dir = parse_line(line)

  if is_dir and id then
    local entry = session.store[id]
    if not entry then return end
    local abs = entry.abs_path
    if session.expanded_dirs[abs] then
      session.expanded_dirs[abs] = nil
      local total = vim.api.nvim_buf_line_count(session.buf)
      local removed_ids = {}
      for j = line_nr + 1, total do
        local l = vim.api.nvim_buf_get_lines(session.buf, j - 1, j, false)[1]
        local _, _, d = parse_line(l)
        if d <= depth then break end
        local cid = l:match('/(%d+) ')
        if cid then removed_ids[tonumber(cid)] = true end
      end
      remove_children_lines(session, session.buf, line_nr, depth)
      if session.id_order and next(removed_ids) then
        local new_order = {}
        for _, oid in ipairs(session.id_order) do
          if not removed_ids[oid] then new_order[#new_order + 1] = oid end
        end
        session.id_order = new_order
      end
    else
      session.expanded_dirs[abs] = true
      local child_lines, new_ids = render_children(session, abs, depth + 1)
      if #child_lines > 0 then
        vim.api.nvim_buf_set_lines(session.buf, line_nr, line_nr, false, child_lines)
        if session.id_order then
          local insert_pos
          for k, oid in ipairs(session.id_order) do
            if oid == id then insert_pos = k; break end
          end
          if insert_pos then
            for k = #new_ids, 1, -1 do
              table.insert(session.id_order, insert_pos + 1, new_ids[k])
            end
          end
        end
      end
    end
    vim.bo[session.buf].modified = false
  elseif id and not is_dir then
    local entry = session.store[id]
    if entry then
      win_mod.open_file(entry.abs_path)
    end
  end
end

local function has_trash()
  return vim.fn.executable('q-trash') == 1
end

local function trash(abs_path)
  local result = vim.system({ 'q-trash', 'rm', '-rf', abs_path }):wait()
  return result.code == 0
end

local function close_bufs_under(abs_path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local buf_path = vim.api.nvim_buf_get_name(buf)
    if buf_path == abs_path or vim.startswith(buf_path, abs_path .. '/') then
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
  end
end

local function rename_bufs(old_path, new_path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local buf_path = vim.api.nvim_buf_get_name(buf)
    if buf_path == old_path or vim.startswith(buf_path, old_path .. '/') then
      local new_buf_path = new_path .. buf_path:sub(#old_path + 1)
      vim.api.nvim_buf_set_name(buf, new_buf_path)
    end
  end
end

compute_actions = function(session, buf_lines)
  local seen_ids = {}
  local stack = { { path = session.root_dir, depth = -1 } }
  local actions = {}
  local transitions = {}

  for _, line in ipairs(buf_lines) do
    local id, name, depth, is_dir = parse_line(line)
    while #stack > 1 and stack[#stack].depth >= depth do
      table.remove(stack)
    end
    local parent_path = stack[#stack].path

    if id then
      seen_ids[id] = true
      transitions[id] = transitions[id] or {}
      local raw_name = is_dir and name:sub(1, -2) or name
      local new_path = parent_path .. '/' .. raw_name
      table.insert(transitions[id], new_path)
      if is_dir then
        table.insert(stack, { path = new_path, depth = depth })
      elseif session.store[id] and session.store[id].type == 'directory' then
        table.insert(stack, { path = session.store[id].abs_path, depth = depth })
      end
    else
      local segments = {}
      for seg in name:gmatch('[^/]+') do
        segments[#segments + 1] = seg
      end
      if is_dir and #segments > 0 then
        local current = parent_path
        for _, seg in ipairs(segments) do
          current = current .. '/' .. seg
          table.insert(actions, { name = 'create', dst = current .. '/' })
        end
        table.insert(stack, { path = parent_path .. '/' .. name:sub(1, -2), depth = depth })
      elseif #segments > 1 then
        local current = parent_path
        for si, seg in ipairs(segments) do
          current = current .. '/' .. seg
          if si < #segments then
            table.insert(actions, { name = 'create', dst = current .. '/' })
          else
            table.insert(actions, { name = 'create', dst = current })
          end
        end
      else
        table.insert(actions, { name = 'create', dst = parent_path .. '/' .. name })
      end
    end
  end

  for id, path in pairs(session.id_to_path) do
    if not seen_ids[id] then
      table.insert(actions, { name = 'delete', src = path })
    end
  end

  for id, new_paths in pairs(transitions) do
    local id_in_snapshot = session.id_to_path[id]
    local old_path = id_in_snapshot or (session.store[id] and session.store[id].abs_path)
    if old_path then
      local keep_original = vim.tbl_contains(new_paths, old_path)
      -- if the entry is not in id_to_path (collapsed), the original file is still on disk
      local collapsed = not id_in_snapshot and session.store[id] ~= nil
      for i, new_path in ipairs(new_paths) do
        if new_path ~= old_path then
          if keep_original or collapsed or i < #new_paths then
            table.insert(actions, { name = 'copy', src = old_path, dst = new_path })
          else
            table.insert(actions, { name = 'move', src = old_path, dst = new_path })
          end
        end
      end
    end
  end

  local seen = {}
  local deduped = {}
  for _, action in ipairs(actions) do
    local key = action.name .. '|' .. (action.src or '') .. '|' .. (action.dst or '')
    if not seen[key] then
      seen[key] = true
      deduped[#deduped + 1] = action
    end
  end

  return deduped
end

local function format_action(action, root_dir)
  local function rel(path)
    if vim.startswith(path, root_dir .. '/') then
      return path:sub(#root_dir + 2)
    end
    return path
  end
  if action.name == 'create' then
    return 'Create', rel(action.dst)
  elseif action.name == 'delete' then
    return 'Delete', rel(action.src)
  elseif action.name == 'move' then
    return 'Move', rel(action.src) .. ' -> ' .. rel(action.dst)
  elseif action.name == 'copy' then
    return 'Copy', rel(action.src) .. ' -> ' .. rel(action.dst)
  end
  return action.name, ''
end

local show_confirmation = vim.schedule_wrap(function(actions, dupes, root_dir, callback)
  local confirm_hl_ns = vim.api.nvim_create_namespace('tree_sidebar_fyler_confirm')
  local action_hls = {
    create = 'DiagnosticInfo',
    delete = 'DiagnosticInfo',
    move = 'DiagnosticWarn',
    copy = 'DiagnosticHint',
  }

  local display_lines = {}
  local hls = {}
  local has_conflict = false
  for _, action in ipairs(actions) do
    local label, detail = format_action(action, root_dir)
    local conflict = false
    if action.dst then
      local check_path = action.dst
      if vim.endswith(check_path, '/') then check_path = check_path:sub(1, -2) end
      if action.name ~= 'create' or not vim.endswith(action.dst, '/') then
        if vim.uv.fs_stat(check_path) then
          local is_self = action.src and (action.src == check_path or action.src:sub(1, -2) == check_path)
          local is_case_rename = action.src and check_path:lower() == action.src:lower()
          if not is_self and not is_case_rename then
            conflict = true
            has_conflict = true
          end
        end
      end
    end
    if conflict then
      detail = detail .. '  [CONFLICT: already exists]'
    end
    local line = label .. ' │ ' .. detail
    display_lines[#display_lines + 1] = line
    local line_idx = #display_lines - 1
    hls[#hls + 1] = { line = line_idx, hl = conflict and 'DiagnosticError' or (action_hls[action.name] or 'Normal'), col_start = 0, col_end = #label }
    hls[#hls + 1] = { line = line_idx, hl = 'FloatBorder', col_start = #label, col_end = #label + 3 }
    hls[#hls + 1] = { line = line_idx, hl = conflict and 'DiagnosticError' or 'Comment', col_start = #label + 3, col_end = #line }
  end

  local has_dupes = #dupes > 0
  if has_dupes then
    has_conflict = true
    for _, dname in ipairs(dupes) do
      local line = 'Duplicate │ ' .. dname
      display_lines[#display_lines + 1] = line
      local line_idx = #display_lines - 1
      hls[#hls + 1] = { line = line_idx, hl = 'DiagnosticError', col_start = 0, col_end = #'Duplicate' }
      hls[#hls + 1] = { line = line_idx, hl = 'FloatBorder', col_start = #'Duplicate', col_end = #'Duplicate' + 3 }
      hls[#hls + 1] = { line = line_idx, hl = 'DiagnosticError', col_start = #'Duplicate' + 3, col_end = #line }
    end
  end

  display_lines[#display_lines + 1] = ''

  local content_width = 0
  for _, line in ipairs(display_lines) do
    content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
  end

  if has_conflict then
    local footer_text = 'Fix conflicts before saving'
    content_width = math.max(content_width, #footer_text)
    display_lines[#display_lines + 1] = footer_text
    local footer_idx = #display_lines - 1
    hls[#hls + 1] = { line = footer_idx, hl = 'DiagnosticError', col_start = 0, col_end = #footer_text }
  else
    local yes_text = '[Y]es'
    local no_text = '[N]o'
    local actions_str = yes_text .. '    ' .. no_text
    content_width = math.max(content_width, #actions_str)
    local width_for_pad = math.min(content_width + 4, vim.o.columns - 4)
    local padding = math.max(0, math.floor((width_for_pad - #actions_str) / 2))
    local actions_line = string.rep(' ', padding) .. actions_str
    display_lines[#display_lines + 1] = actions_line
    local actions_line_idx = #display_lines - 1
    local yes_start = padding
    local no_start = padding + #yes_text + 4
    hls[#hls + 1] = { line = actions_line_idx, hl = 'Special', col_start = yes_start, col_end = yes_start + 3 }
    hls[#hls + 1] = { line = actions_line_idx, hl = 'Special', col_start = no_start, col_end = no_start + 3 }
  end

  local width = math.min(content_width + 4, vim.o.columns - 4)
  local height = math.min(#display_lines, vim.o.lines - 4)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false

  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, confirm_hl_ns, hl.line, hl.col_start, {
      hl_group = hl.hl,
      end_row = hl.line,
      end_col = hl.col_end,
    })
  end

  local confirm_text = has_conflict and ' Conflicts detected ' or ' Want to continue? '

  local win = vim.api.nvim_open_win(buf, true, {
    border = 'rounded',
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    height = height,
    relative = 'editor',
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    style = 'minimal',
    title = confirm_text,
    title_pos = 'center',
    width = width,
  })

  local closed = false
  local function close(confirmed)
    if closed then return end
    closed = true
    pcall(vim.api.nvim_win_close, win, true)
    callback(confirmed)
  end

  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf, once = true, nested = true,
    callback = function() close(false) end,
  })

  local opts = { buffer = buf, nowait = true }
  if has_conflict then
    vim.keymap.set('n', '<CR>', function() close(false) end, opts)
    vim.keymap.set('n', '<Esc>', function() close(false) end, opts)
    vim.keymap.set('n', 'q', function() close(false) end, opts)
  else
    vim.keymap.set('n', 'y', function() close(true) end, opts)
    vim.keymap.set('n', 'Y', function() close(true) end, opts)
    vim.keymap.set('n', '<CR>', function() close(true) end, opts)
    vim.keymap.set('n', 'n', function() close(false) end, opts)
    vim.keymap.set('n', 'N', function() close(false) end, opts)
    vim.keymap.set('n', '<Esc>', function() close(false) end, opts)
    vim.keymap.set('n', 'q', function() close(false) end, opts)
  end
end)

local function execute_actions(actions)
  local ordered = {}
  for _, a in ipairs(actions) do
    if a.name == 'create' then table.insert(ordered, a) end
  end
  for _, a in ipairs(actions) do
    if a.name == 'move' then table.insert(ordered, a) end
  end
  for _, a in ipairs(actions) do
    if a.name == 'copy' then table.insert(ordered, a) end
  end
  for _, a in ipairs(actions) do
    if a.name == 'delete' then table.insert(ordered, a) end
  end

  for _, action in ipairs(ordered) do
    if action.name == 'create' then
      if vim.endswith(action.dst, '/') then
        vim.fn.mkdir(action.dst:sub(1, -2), 'p')
      else
        local parent = vim.fs.dirname(action.dst)
        vim.fn.mkdir(parent, 'p')
        local fd = vim.uv.fs_open(action.dst, 'w', 420)
        if fd then vim.uv.fs_close(fd) end
      end
    elseif action.name == 'delete' then
      if has_trash() then
        trash(action.src)
      else
        vim.fn.delete(action.src, 'rf')
      end
      close_bufs_under(action.src)
    elseif action.name == 'move' then
      local src = action.src
      if vim.endswith(src, '/') then src = src:sub(1, -2) end
      local dst = action.dst
      if vim.endswith(dst, '/') then dst = dst:sub(1, -2) end
      local new_parent = vim.fs.dirname(dst)
      if not vim.uv.fs_stat(new_parent) then
        vim.fn.mkdir(new_parent, 'p')
      end
      vim.uv.fs_rename(src, dst)
      rename_bufs(src, dst)
    elseif action.name == 'copy' then
      local src = action.src
      if vim.endswith(src, '/') then src = src:sub(1, -2) end
      local dst = action.dst
      if vim.endswith(dst, '/') then dst = dst:sub(1, -2) end
      vim.fn.system({ 'cp', '-r', src, dst })
    end
  end
end

check_duplicates = function(session, buf_lines)
  local stack = { { path = session.root_dir, depth = -1 } }
  local seen_names = {}
  local dupes = {}

  for _, line in ipairs(buf_lines) do
    local _, name, depth, is_dir = parse_line(line)
    if name == '' then goto continue end
    while #stack > 1 and stack[#stack].depth >= depth do
      table.remove(stack)
    end
    local parent_path = stack[#stack].path
    local raw_name = is_dir and name:sub(1, -2) or name
    local key = parent_path .. '/' .. raw_name
    if seen_names[key] then
      dupes[#dupes + 1] = raw_name
    else
      seen_names[key] = true
    end
    if is_dir then
      table.insert(stack, { path = parent_path .. '/' .. raw_name, depth = depth })
    end
    ::continue::
  end
  return dupes
end

local function mutate(session)
  if not vim.bo[session.buf].modified then return end

  local buf_lines = vim.tbl_filter(function(l)
    return #l > 0
  end, vim.api.nvim_buf_get_lines(session.buf, 0, -1, false))

  local dupes = check_duplicates(session, buf_lines)
  local actions = compute_actions(session, buf_lines)

  if #actions == 0 and #dupes == 0 then
    vim.bo[session.buf].modified = false
    return
  end

  show_confirmation(actions, dupes, session.root_dir, function(confirmed)
    if not confirmed then return end

    execute_actions(actions)

    session.store = {}
    session.next_id = 1
    session.id_to_path = {}

    local lines = render_to_lines(session)
    vim.api.nvim_buf_set_lines(session.buf, 0, -1, false, lines)
    refresh_decorations(session, session.buf)
    vim.bo[session.buf].modified = false

    local sidebar_state = require('lu5je0.ext.tree-sidebar.state')
    if sidebar_state:is_open() then
      local ok, files = pcall(require, 'lu5je0.ext.tree-sidebar.sources.files')
      if ok then files.refresh() end
    end
  end)
end

-- Returns the byte column where the file name starts (after indent + concealed ID)
local function name_start_col(line)
  local after_id = line:match('^%s*/%d+ ()')
  if after_id then return after_id - 1 end
  local indent = line:match('^(%s*)')
  return #indent
end

function M.open(node, opts)
  opts = opts or {}
  local state = require('lu5je0.ext.tree-sidebar.state')
  local root_dir = node.type == 'directory' and node.abs_path or vim.fs.dirname(node.abs_path)

  -- reuse existing session if buffer is still valid
  for b, s in pairs(sessions) do
    if s.root_dir == root_dir and vim.api.nvim_buf_is_valid(b) then
      if opts.replace then
        vim.api.nvim_win_set_buf(0, b)
      else
        local target, cancelled = win_mod.get_target_win()
        if cancelled then return end
        if not target then
          vim.cmd('belowright vsplit')
        else
          vim.api.nvim_set_current_win(target)
        end
        vim.api.nvim_win_set_buf(0, b)
      end
      return
    end
  end

  local session = {
    root_dir = root_dir,
    store = {},
    next_id = 1,
    id_to_path = {},
    expanded_dirs = {},
  }

  if state.files and state.files.root then
    local sidebar_node = find_sidebar_node(state.files.root, root_dir)
    if sidebar_node then
      seed_expanded(session, sidebar_node)
    end
  end

  local lines = render_to_lines(session)

  local buf = vim.api.nvim_create_buf(true, false)
  session.buf = buf
  vim.api.nvim_buf_set_name(buf, 'tree-edit://' .. root_dir)
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].filetype = 'tree_edit'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].expandtab = true
  vim.bo[buf].shiftwidth = 2

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  refresh_decorations(session, buf)
  vim.bo[buf].modified = false

  if opts.replace then
    local old_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_buf(0, buf)
    if vim.api.nvim_buf_is_valid(old_buf) and not vim.bo[old_buf].modified and old_buf ~= buf then
      pcall(vim.api.nvim_buf_delete, old_buf, {})
    end
  else
    local target, cancelled = win_mod.get_target_win()
    if cancelled then
      vim.api.nvim_buf_delete(buf, { force = true })
      return
    end
    if not target then
      vim.cmd('belowright vsplit')
    else
      vim.api.nvim_set_current_win(target)
    end
    vim.api.nvim_win_set_buf(0, buf)
  end
  session.win = vim.api.nvim_get_current_win()

  vim.wo[session.win].concealcursor = 'nvic'
  vim.wo[session.win].conceallevel = 3
  vim.wo[session.win].number = true
  vim.wo[session.win].signcolumn = 'auto'

  vim.cmd([[syn match TreeEditStoreID /\/\d\+\s/ conceal]])

  sessions[buf] = session

  local refresh_timer = nil

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function() mutate(session) end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function()
      sessions[buf] = nil
      if refresh_timer then
        pcall(function() refresh_timer:stop(); refresh_timer:close() end)
        refresh_timer = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufWinEnter', {
    buffer = buf,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      vim.wo[win].concealcursor = 'nvic'
      vim.wo[win].conceallevel = 3
    end,
  })
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if refresh_timer then
        refresh_timer:stop()
        refresh_timer:close()
      end
      refresh_timer = vim.uv.new_timer()
      refresh_timer:start(50, 0, vim.schedule_wrap(function()
        refresh_timer = nil
        if vim.api.nvim_buf_is_valid(buf) then
          refresh_decorations(session, buf)
          refresh_diff_signs(session, buf)
        end
      end))
    end,
  })

  local function close_buf()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modified = false
    local win = vim.api.nvim_get_current_win()
    local winbar_state = require('lu5je0.ext.winbar.state')
    local win_bufs = winbar_state.win_bufs[win]
    if win_bufs and vim.api.nvim_win_get_buf(win) == buf then
      local filtered = {}
      local cur_idx
      for _, b in ipairs(win_bufs) do
        if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then
          filtered[#filtered + 1] = b
          if b == buf then cur_idx = #filtered end
        end
      end
      if cur_idx and #filtered > 1 then
        local t = filtered[cur_idx < #filtered and cur_idx + 1 or cur_idx - 1]
        vim.api.nvim_set_current_buf(t)
      end
    end
    pcall(vim.cmd, 'bdelete ' .. buf)
  end

  local function quit_with_check()
    if vim.bo[buf].modified then
      local choice = vim.fn.confirm('Discard unsaved changes?', '&Yes\n&No', 2)
      if choice ~= 1 then return end
    end
    close_buf()
  end

  local function smart_paste(put_cmd)
    local cur_line = vim.api.nvim_get_current_line()
    local cur_id, _, cur_depth, cur_is_dir = parse_line(cur_line)
    local is_expanded = false
    if cur_is_dir and cur_id and session.store[cur_id] then
      is_expanded = session.expanded_dirs[session.store[cur_id].abs_path] == true
    end
    local target_depth = (cur_is_dir and is_expanded) and (cur_depth + 1) or cur_depth

    local before = vim.api.nvim_buf_line_count(buf)
    vim.cmd('normal! ' .. put_cmd)
    local after = vim.api.nvim_buf_line_count(buf)
    local pasted_count = after - before
    if pasted_count <= 0 then return end

    local paste_start = vim.api.nvim_win_get_cursor(0)[1]
    local paste_end = paste_start + pasted_count - 1

    local target_indent = string.rep('  ', target_depth)
    for i = paste_start, paste_end do
      local l = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1]
      local stripped = l:match('^%s*(.*)$')
      vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { target_indent .. stripped })
    end
  end

  -- Cursor: snap to name start, skip concealed /NNN
  local function snap_to_name_start()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    if not line then return end
    local ns = name_start_col(line)
    if col < ns then
      vim.api.nvim_win_set_cursor(0, { row, ns })
    end
  end

  local function vertical_move(dir)
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    local offset = col - name_start_col(line or '')

    vim.cmd('normal! ' .. dir)

    local new_row = vim.api.nvim_win_get_cursor(0)[1]
    local new_line = vim.api.nvim_buf_get_lines(buf, new_row - 1, new_row, false)[1]
    if not new_line then return end
    local ns = name_start_col(new_line)
    local tgt = ns + math.max(0, offset)
    local max_col = math.max(0, #new_line - 1)
    if tgt > max_col then tgt = max_col end
    vim.api.nvim_win_set_cursor(0, { new_row, tgt })
  end

  local function preview_hunk()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    if not line then return end
    local id, name, _, is_dir = parse_line(line)

    local content = {}
    local old_path = id and (session.id_to_path[id] or (session.store[id] and session.store[id].abs_path))
    if id and old_path then
      local old_name = session.store[id] and session.store[id].name or vim.fs.basename(old_path)
      local raw_name = is_dir and name:sub(1, -2) or name
      if raw_name ~= old_name then
        content[#content + 1] = '- ' .. old_name
        content[#content + 1] = '+ ' .. raw_name
      else
        vim.notify('No change at cursor', vim.log.levels.INFO)
        return
      end
    elseif not id then
      content[#content + 1] = '+ ' .. (name or '')
    else
      vim.notify('No change at cursor', vim.log.levels.INFO)
      return
    end

    if #content == 0 then return end
    local pbuf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, content)
    vim.bo[pbuf].filetype = 'diff'
    vim.bo[pbuf].modifiable = false
    local w = 0
    for _, l in ipairs(content) do
      w = math.max(w, vim.fn.strdisplaywidth(l))
    end
    w = math.min(math.max(w + 2, 20), vim.o.columns - 4)
    vim.api.nvim_open_win(pbuf, false, {
      relative = 'cursor', row = 1, col = 0,
      width = w, height = #content,
      style = 'minimal', border = 'rounded', focusable = false,
    })
    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'BufLeave' }, {
      buffer = buf, once = true,
      callback = function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == pbuf then
            vim.api.nvim_win_close(win, true)
          end
        end
        if vim.api.nvim_buf_is_valid(pbuf) then
          vim.api.nvim_buf_delete(pbuf, { force = true })
        end
      end,
    })
  end

  local function reset_hunk()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    if not line then return end
    local id, name, depth, is_dir = parse_line(line)

    local old_path = id and (session.id_to_path[id] or (session.store[id] and session.store[id].abs_path))
    if id and old_path then
      local entry = session.store[id]
      if not entry then return end
      local old_name = entry.name
      local raw_name = is_dir and name:sub(1, -2) or name
      if raw_name == old_name then
        vim.notify('No change at cursor', vim.log.levels.INFO)
        return
      end
      local indent = string.rep('  ', depth)
      local restored = entry.type == 'directory' and (old_name .. '/') or old_name
      vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { string.format('%s/%d %s', indent, id, restored) })
    elseif not id then
      vim.api.nvim_buf_set_lines(buf, row - 1, row, false, {})
    end
  end

  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = buf,
    callback = snap_to_name_start,
  })

  vim.keymap.set('n', 'j', function() vertical_move('j') end, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'k', function() vertical_move('k') end, { buffer = buf, nowait = true })

  vim.keymap.set('n', 'p', function() smart_paste('"0p') end, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'P', function() smart_paste('"0P') end, { buffer = buf, nowait = true })

  vim.keymap.set('n', '<leader>gg', preview_hunk, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<leader>gu', reset_hunk, { buffer = buf, nowait = true })

  vim.keymap.set('n', '<CR>', function() on_enter(session) end, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'q', close_buf, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<leader>q', quit_with_check, { buffer = buf, nowait = true })
end

function M.open_dir(dir_path)
  dir_path = vim.fn.fnamemodify(dir_path, ':p'):gsub('/$', '')
  M.open({ type = 'directory', abs_path = dir_path }, { replace = true })
end

M._parse_line = parse_line
M._compute_actions = compute_actions

return M
