local tree = require('lu5je0.ext.tree-sidebar.sources.files.tree')
local win_mod = require('lu5je0.ext.tree-sidebar.window')
local actions_mod = require('lu5je0.ext.tree-sidebar.sources.files.tree-edit.actions')
local te_render = require('lu5je0.ext.tree-sidebar.sources.files.tree-edit.render')
local confirm = require('lu5je0.ext.tree-sidebar.sources.files.tree-edit.confirm')

local parse_line = actions_mod.parse_line
local compute_actions = actions_mod.compute_actions
local check_duplicates = actions_mod.check_duplicates
local execute_actions = actions_mod.execute_actions
local refresh_decorations = te_render.refresh_decorations
local refresh_diff_signs = te_render.refresh_diff_signs

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

local function count_entries(session, dir_path)
  local count = 0
  local entries = tree.scan_dir(dir_path)
  for _, entry in ipairs(entries) do
    count = count + 1
    if entry.type == 'directory' and session.expanded_dirs[entry.abs_path] then
      count = count + count_entries(session, entry.abs_path)
    end
  end
  return count
end

local function render_to_lines(session)
  local total = session.next_id + count_entries(session, session.root_dir)
  local id_width = math.max(1, #tostring(total))
  session._id_width = id_width
  local fmt = '%s/%0' .. id_width .. 'd %s'

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
      lines[#lines + 1] = string.format(fmt, indent, id, name)
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
  local id_width = session._id_width or 1
  local fmt = '%s/%0' .. id_width .. 'd %s'
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
      lines[#lines + 1] = string.format(fmt, indent, id, name)
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

  confirm.show(actions, dupes, session.root_dir, function(confirmed)
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
  vim.wo[session.win].signcolumn = 'yes:1'

  vim.cmd([[syn match TreeEditStoreID /\/\d\+\s/ conceal]])

  sessions[buf] = session

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function() mutate(session) end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function() sessions[buf] = nil end,
  })

  vim.api.nvim_create_autocmd('BufWinEnter', {
    buffer = buf,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      vim.wo[win].concealcursor = 'nvic'
      vim.wo[win].conceallevel = 3
    end,
  })

  local refresh_pending = false
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if refresh_pending then return end
      refresh_pending = true
      vim.schedule(function()
        refresh_pending = false
        if vim.api.nvim_buf_is_valid(buf) then
          refresh_decorations(session, buf)
          refresh_diff_signs(session, buf)
        end
      end)
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

  local function is_line_changed(line, id_counts)
    if not line or line == '' then return false end
    local id, name, _, is_dir = parse_line(line)
    if not id then return true end
    if id_counts and id_counts[id] and id_counts[id] > 1 then return true end
    local old_path = session.id_to_path[id] or (session.store[id] and session.store[id].abs_path)
    if not old_path then return false end
    local entry = session.store[id]
    if not entry then return false end
    local raw_name = is_dir and name:sub(1, -2) or name
    return raw_name ~= entry.name
  end

  local function reset_hunk()
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    local id_counts = {}
    local seen_ids = {}
    for _, l in ipairs(all_lines) do
      local lid = parse_line(l)
      if lid then
        seen_ids[lid] = true
        id_counts[lid] = (id_counts[lid] or 0) + 1
      end
    end

    local deleted_to_restore = {}
    if session.id_order then
      local id_to_line = {}
      for i, l in ipairs(all_lines) do
        local lid = parse_line(l)
        if lid then id_to_line[lid] = i end
      end

      for idx, oid in ipairs(session.id_order) do
        if session.id_to_path[oid] and not seen_ids[oid] then
          local neighbor_line
          for k = idx - 1, 1, -1 do
            if id_to_line[session.id_order[k]] then
              neighbor_line = id_to_line[session.id_order[k]]
              break
            end
          end
          if not neighbor_line then
            for k = idx + 1, #session.id_order do
              if id_to_line[session.id_order[k]] then
                neighbor_line = id_to_line[session.id_order[k]]
                break
              end
            end
          end
          if neighbor_line == cursor_row then
            deleted_to_restore[#deleted_to_restore + 1] = { id = oid, after_idx = idx }
          end
        end
      end
    end

    local has_changed_line = is_line_changed(all_lines[cursor_row], id_counts)

    if not has_changed_line and #deleted_to_restore == 0 then
      vim.notify('No change at cursor', vim.log.levels.INFO)
      return
    end

    if has_changed_line then
      local hunk_start = cursor_row
      while hunk_start > 1 and is_line_changed(all_lines[hunk_start - 1], id_counts) do
        hunk_start = hunk_start - 1
      end
      local hunk_end = cursor_row
      while hunk_end < #all_lines and is_line_changed(all_lines[hunk_end + 1], id_counts) do
        hunk_end = hunk_end + 1
      end

      local ids_before_hunk = {}
      for i = 1, hunk_start - 1 do
        local lid = parse_line(all_lines[i])
        if lid then ids_before_hunk[lid] = true end
      end

      for i = hunk_end, hunk_start, -1 do
        local id, _, depth = parse_line(all_lines[i])
        if not id then
          vim.api.nvim_buf_set_lines(buf, i - 1, i, false, {})
        elseif ids_before_hunk[id] then
          vim.api.nvim_buf_set_lines(buf, i - 1, i, false, {})
        else
          local entry = session.store[id]
          if entry then
            local indent = string.rep('  ', depth)
            local restored = entry.type == 'directory' and (entry.name .. '/') or entry.name
            local fmt = '%s/%0' .. (session._id_width or 1) .. 'd %s'
            vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { string.format(fmt, indent, id, restored) })
          end
          ids_before_hunk[id] = true
        end
      end
    end

    if #deleted_to_restore > 0 then
      table.sort(deleted_to_restore, function(a, b) return a.after_idx > b.after_idx end)
      for _, del in ipairs(deleted_to_restore) do
        local entry = session.store[del.id]
        if entry then
          local rel = entry.abs_path:sub(#session.root_dir + 2)
          local depth = 0
          for _ in rel:gmatch('/') do depth = depth + 1 end
          local indent = string.rep('  ', depth)
          local restored = entry.type == 'directory' and (entry.name .. '/') or entry.name
          local fmt = '%s/%0' .. (session._id_width or 1) .. 'd %s'
          local restored_line = string.format(fmt, indent, del.id, restored)
          vim.api.nvim_buf_set_lines(buf, cursor_row, cursor_row, false, { restored_line })
        end
      end
    end
  end

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'ModeChanged' }, {
    buffer = buf,
    callback = snap_to_name_start,
  })

  vim.keymap.set('n', 'j', function() vertical_move('j') end, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'k', function() vertical_move('k') end, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'J', '<nop>', { buffer = buf, nowait = true })
  vim.keymap.set('n', 'gJ', '<nop>', { buffer = buf, nowait = true })

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
