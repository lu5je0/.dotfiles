local tree = require('lu5je0.ext.tree-sidebar.sources.files.tree')
local win_mod = require('lu5je0.ext.tree-sidebar.window')
local actions_mod = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.actions')
local te_render = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.render')
local confirm = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.confirm')

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
  local existing = session.path_to_id[abs_path]
  if existing then return existing end
  local id = session.next_id
  session.next_id = id + 1
  session.store[id] = { name = name, abs_path = abs_path, type = entry_type }
  session.id_to_path[id] = abs_path
  session.path_to_id[abs_path] = id
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
    if l ~= '' and l:match('%S') then
      local _, _, d = parse_line(l)
      if d <= depth then break end
      local cid = l:match('/(%d+) ')
      if cid then
        session.id_to_path[tonumber(cid)] = nil
      end
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
      local child_lines_cache = {}
      for j = line_nr + 1, total do
        local l = vim.api.nvim_buf_get_lines(session.buf, j - 1, j, false)[1]
        if l ~= '' and l:match('%S') then
          local _, _, d = parse_line(l)
          if d <= depth then break end
          child_lines_cache[#child_lines_cache + 1] = l
          local cid = l:match('/(%d+) ')
          if cid then removed_ids[tonumber(cid)] = true end
        end
      end
      if #child_lines_cache > 0 then
        local disk_lines, _ = render_children(session, abs, depth + 1)
        local has_diff = #disk_lines ~= #child_lines_cache
        if not has_diff then
          for ci = 1, #child_lines_cache do
            if child_lines_cache[ci] ~= disk_lines[ci] then
              has_diff = true
              break
            end
          end
        end
        if has_diff then
          session.saved_children[abs] = child_lines_cache
        else
          session.saved_children[abs] = nil
        end
      else
        session.saved_children[abs] = nil
      end
      remove_children_lines(session, session.buf, line_nr, depth)
      if session.id_order and next(removed_ids) then
        local new_order = {}
        for _, oid in ipairs(session.id_order) do
          if not removed_ids[oid] then new_order[#new_order + 1] = oid end
        end
        session.id_order = new_order
      end
      refresh_decorations(session, session.buf)
    else
      session.expanded_dirs[abs] = true
      local child_lines, new_ids
      local cached = session.saved_children[abs]
      if cached then
        child_lines = cached
        session.saved_children[abs] = nil
        new_ids = {}
        for _, l in ipairs(child_lines) do
          local cid = l:match('/(%d+) ')
          if cid then new_ids[#new_ids + 1] = tonumber(cid) end
        end
      else
        child_lines, new_ids = render_children(session, abs, depth + 1)
      end
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
      refresh_decorations(session, session.buf)
    end
    if not next(session.saved_children) then
      vim.bo[session.buf].modified = false
    end
  elseif id and not is_dir then
    local entry = session.store[id]
    if entry then
      win_mod.open_file(entry.abs_path)
    end
  end
end

local function mutate(session)
  if not vim.bo[session.buf].modified then return end

  local raw_lines = vim.tbl_filter(function(l)
    return #l > 0
  end, vim.api.nvim_buf_get_lines(session.buf, 0, -1, false))

  local buf_lines = {}
  for _, l in ipairs(raw_lines) do
    buf_lines[#buf_lines + 1] = l
    local lid, _, _, lis_dir = parse_line(l)
    if lis_dir and lid and session.store[lid] then
      local labs = session.store[lid].abs_path
      if not session.expanded_dirs[labs] and session.saved_children[labs] then
        for _, cl in ipairs(session.saved_children[labs]) do
          buf_lines[#buf_lines + 1] = cl
        end
      end
    end
  end

  local dupes = check_duplicates(session, buf_lines)
  local actions = compute_actions(session, buf_lines)

  if #actions == 0 and #dupes == 0 then
    vim.bo[session.buf].modified = false
    return
  end

  actions_mod.add_implicit_creates(actions, session.root_dir)

  confirm.show(actions, dupes, session.root_dir, function(confirmed)
    if not confirmed then return end

    execute_actions(actions)

    session.store = {}
    session.next_id = 1
    session.id_to_path = {}
    session.path_to_id = {}
    session.saved_children = {}

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
      if opts.replace or opts.inplace then
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
    path_to_id = {},
    expanded_dirs = {},
    saved_children = {},
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
  vim.api.nvim_buf_set_name(buf, 'fs-edit://' .. root_dir)
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].filetype = 'fs_edit'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].expandtab = true
  vim.bo[buf].shiftwidth = 2
  vim.b[buf].winbar_display = {
    name = (vim.fs.basename(root_dir) ~= '' and vim.fs.basename(root_dir) or root_dir) .. '/',
    icon = '',
    icon_hl = 'Directory'
  }

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  refresh_decorations(session, buf)
  vim.bo[buf].modified = false

  if opts.replace then
    local old_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_buf(0, buf)
    if vim.api.nvim_buf_is_valid(old_buf) and not vim.bo[old_buf].modified and old_buf ~= buf then
      pcall(vim.api.nvim_buf_delete, old_buf, {})
    end
  elseif opts.inplace then
    vim.api.nvim_win_set_buf(0, buf)
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

  vim.cmd([[syn match FsEditStoreID /^\s*\zs\/\d\+\s/ conceal]])

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
    require('lu5je0.ext.winbar.actions').bdelete_safe(buf)
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

    local pasted = vim.api.nvim_buf_get_lines(buf, paste_start - 1, paste_end, false)
    local min_indent
    for _, l in ipairs(pasted) do
      if l:match('%S') then
        local indent = #(l:match('^(%s*)') or '')
        if not min_indent or indent < min_indent then min_indent = indent end
      end
    end
    min_indent = min_indent or 0

    local target_prefix = string.rep('  ', target_depth)
    local rewritten = {}
    for i, l in ipairs(pasted) do
      if l:match('%S') then
        local indent = l:match('^(%s*)') or ''
        local extra = math.max(0, #indent - min_indent)
        rewritten[i] = target_prefix .. string.rep(' ', extra) .. l:sub(#indent + 1)
      else
        rewritten[i] = l
      end
    end
    vim.api.nvim_buf_set_lines(buf, paste_start - 1, paste_end, false, rewritten)
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
      -- compute current path via stack scan
      local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local pstack = { { path = session.root_dir, depth = -1 } }
      local cur_path
      for li = 1, row do
        local lid, lname, ldepth, lis_dir = parse_line(all[li])
        while #pstack > 1 and pstack[#pstack].depth >= ldepth do
          table.remove(pstack)
        end
        if li == row then
          local raw = is_dir and name:sub(1, -2) or name
          cur_path = pstack[#pstack].path .. '/' .. raw
        else
          if lid and lis_dir then
            local raw = lname:sub(1, -2)
            table.insert(pstack, { path = pstack[#pstack].path .. '/' .. raw, depth = ldepth })
          elseif lid and session.store[lid] and session.store[lid].type == 'directory' then
            table.insert(pstack, { path = session.store[lid].abs_path, depth = ldepth })
          elseif not lid and lis_dir then
            local raw = lname:sub(1, -2)
            table.insert(pstack, { path = pstack[#pstack].path .. '/' .. raw, depth = ldepth })
          end
        end
      end
      if cur_path and cur_path ~= old_path then
        local rel_old = old_path:sub(#session.root_dir + 2)
        local rel_new = cur_path:sub(#session.root_dir + 2)
        content[#content + 1] = '- ' .. rel_old
        content[#content + 1] = '+ ' .. rel_new
      elseif cur_path and cur_path == old_path then
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
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    local cursor_line = all_lines[cursor_row]
    if cursor_line then
      local cid, _, _, cis_dir = parse_line(cursor_line)
      if cis_dir and cid and session.store[cid] then
        local cabs = session.store[cid].abs_path
        if not session.expanded_dirs[cabs] and session.saved_children[cabs] then
          session.saved_children[cabs] = nil
          refresh_decorations(session, buf)
          refresh_diff_signs(session, buf)
          return
        end
      end
    end

    -- use compute_actions to find what's actually changed
    local buf_lines = {}
    local line_map = {} -- filtered_idx -> 1-based line number
    for i, l in ipairs(all_lines) do
      if #l > 0 then
        buf_lines[#buf_lines + 1] = l
        line_map[#buf_lines] = i
      end
    end

    local act = compute_actions(session, buf_lines)
    local dupes = check_duplicates(session, buf_lines)
    if #act == 0 and #dupes == 0 then
      vim.notify('No change at cursor', vim.log.levels.INFO)
      return
    end

    -- build set of changed line numbers (1-based)
    -- per-line path check (same as refresh_diff_signs)
    local changed_set = {}
    local stack = { { path = session.root_dir, depth = -1 } }
    for i = 1, #buf_lines do
      local id, name, depth, is_dir = parse_line(buf_lines[i])
      while #stack > 1 and stack[#stack].depth >= depth do
        table.remove(stack)
      end
      local parent_path = stack[#stack].path

      if id then
        local raw_name = is_dir and name:sub(1, -2) or name
        local new_path = parent_path .. '/' .. raw_name
        local old_path = session.id_to_path[id] or (session.store[id] and session.store[id].abs_path)
        if old_path and new_path ~= old_path then
          changed_set[line_map[i]] = true
        end
        if is_dir then
          table.insert(stack, { path = new_path, depth = depth })
        elseif session.store[id] and session.store[id].type == 'directory' then
          table.insert(stack, { path = session.store[id].abs_path, depth = depth })
        end
      else
        if name and name ~= '' then
          changed_set[line_map[i]] = true
        end
        if is_dir then
          table.insert(stack, { path = parent_path .. '/' .. name:sub(1, -2), depth = depth })
        end
      end
    end

    -- also mark duplicate lines
    if #dupes > 0 then
      local id_counts = {}
      for _, l in ipairs(all_lines) do
        local lid = parse_line(l)
        if lid then id_counts[lid] = (id_counts[lid] or 0) + 1 end
      end
      for i, l in ipairs(all_lines) do
        local lid = parse_line(l)
        if lid and id_counts[lid] > 1 then
          changed_set[i] = true
        end
      end
    end

    -- also check for deleted entries at cursor
    local deleted_to_restore = {}
    if session.id_order then
      local seen_ids = {}
      for _, l in ipairs(all_lines) do
        local lid = parse_line(l)
        if lid then seen_ids[lid] = true end
      end
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
              neighbor_line = id_to_line[session.id_order[k]]; break
            end
          end
          if not neighbor_line then
            for k = idx + 1, #session.id_order do
              if id_to_line[session.id_order[k]] then
                neighbor_line = id_to_line[session.id_order[k]]; break
              end
            end
          end
          if neighbor_line == cursor_row then
            deleted_to_restore[#deleted_to_restore + 1] = { id = oid, after_idx = idx }
          end
        end
      end
    end

    if not changed_set[cursor_row] and #deleted_to_restore == 0 then
      vim.notify('No change at cursor', vim.log.levels.INFO)
      return
    end

    -- expand hunk from cursor
    if changed_set[cursor_row] then
      local hunk_start = cursor_row
      while hunk_start > 1 and changed_set[hunk_start - 1] do
        hunk_start = hunk_start - 1
      end
      local hunk_end = cursor_row
      while hunk_end < #all_lines and changed_set[hunk_end + 1] do
        hunk_end = hunk_end + 1
      end

      local ids_before_hunk = {}
      for i = 1, hunk_start - 1 do
        local lid = parse_line(all_lines[i])
        if lid then ids_before_hunk[lid] = true end
      end

      local fmt = '%s/%0' .. (session._id_width or 1) .. 'd %s'
      for i = hunk_end, hunk_start, -1 do
        local id = parse_line(all_lines[i])
        if not id then
          vim.api.nvim_buf_set_lines(buf, i - 1, i, false, {})
        elseif ids_before_hunk[id] then
          vim.api.nvim_buf_set_lines(buf, i - 1, i, false, {})
        else
          local entry = session.store[id]
          if entry then
            local rel = entry.abs_path:sub(#session.root_dir + 2)
            local orig_depth = 0
            for _ in rel:gmatch('/') do orig_depth = orig_depth + 1 end
            local indent = string.rep('  ', orig_depth)
            local restored = entry.type == 'directory' and (entry.name .. '/') or entry.name
            vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { string.format(fmt, indent, id, restored) })
          end
          ids_before_hunk[id] = true
        end
      end
    end

    -- restore deleted entries
    if #deleted_to_restore > 0 then
      table.sort(deleted_to_restore, function(a, b) return a.after_idx > b.after_idx end)
      local fmt = '%s/%0' .. (session._id_width or 1) .. 'd %s'
      for _, del in ipairs(deleted_to_restore) do
        local entry = session.store[del.id]
        if entry then
          local rel = entry.abs_path:sub(#session.root_dir + 2)
          local depth = 0
          for _ in rel:gmatch('/') do depth = depth + 1 end
          local indent = string.rep('  ', depth)
          local restored = entry.type == 'directory' and (entry.name .. '/') or entry.name
          vim.api.nvim_buf_set_lines(buf, cursor_row, cursor_row, false, { string.format(fmt, indent, del.id, restored) })
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

  local function open_new_line(direction)
    local cur_line = vim.api.nvim_get_current_line()
    local cur_id, _, cur_depth, cur_is_dir = parse_line(cur_line)
    local is_expanded = false
    if cur_is_dir and cur_id and session.store[cur_id] then
      is_expanded = session.expanded_dirs[session.store[cur_id].abs_path] == true
    end
    local target_depth = (direction == 'o' and cur_is_dir and is_expanded) and (cur_depth + 1) or cur_depth
    local indent = string.rep('  ', target_depth)
    local placeholder = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.actions').PLACEHOLDER

    local row = vim.api.nvim_win_get_cursor(0)[1]
    local insert_row = direction == 'o' and row or (row - 1)
    vim.api.nvim_buf_set_lines(buf, insert_row, insert_row, false, { indent .. placeholder })
    vim.api.nvim_win_set_cursor(0, { insert_row + 1, #indent + #placeholder })
    vim.cmd('startinsert!')
  end

  vim.keymap.set('n', 'p', function() smart_paste('p') end, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'P', function() smart_paste('P') end, { buffer = buf, nowait = true })

  vim.keymap.set('n', 'o', function() open_new_line('o') end, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'O', function() open_new_line('O') end, { buffer = buf, nowait = true })

  vim.keymap.set('n', '<leader>gg', preview_hunk, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<leader>gu', reset_hunk, { buffer = buf, nowait = true })

  vim.api.nvim_create_autocmd('BufReadCmd', {
    buffer = buf,
    callback = function()
      if vim.bo[buf].modified then
        local choice = vim.fn.confirm('Discard unsaved changes and refresh?', '&Yes\n&No', 2)
        if choice ~= 1 then return end
      end
      session.store = {}
      session.next_id = 1
      session.id_to_path = {}
      session.path_to_id = {}
      session.saved_children = {}
      local lines = render_to_lines(session)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      refresh_decorations(session, buf)
      vim.cmd([[syn match FsEditStoreID /^\s*\zs\/\d\+\s/ conceal]])
      vim.bo[buf].modified = false
    end,
  })

  vim.keymap.set('n', '<CR>', function() on_enter(session) end, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'q', close_buf, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<leader>q', quit_with_check, { buffer = buf, nowait = true })
end

function M.open_dir(dir_path, opts)
  opts = opts or {}
  dir_path = vim.fn.fnamemodify(dir_path, ':p'):gsub('/$', '')
  local replace = opts.replace
  if replace == nil then replace = true end
  M.open({ type = 'directory', abs_path = dir_path }, { replace = replace, inplace = opts.inplace })
end

M._parse_line = parse_line
M._compute_actions = compute_actions

return M
