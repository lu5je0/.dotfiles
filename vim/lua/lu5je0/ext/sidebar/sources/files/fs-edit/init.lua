local win_mod = require('lu5je0.ext.sidebar.window')
local fmt = require('lu5je0.ext.sidebar.sources.files.fs-edit.format')
local model_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.model')
local actions_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions')
local te_render = require('lu5je0.ext.sidebar.sources.files.fs-edit.render')
local confirm = require('lu5je0.ext.sidebar.sources.files.fs-edit.confirm')
local pu = require('lu5je0.ext.sidebar.sources.files.fs-edit.path_util')

local parse_line = fmt.parse_line
local format_line = fmt.format_line

local M = {}

-- session = model table extended with { buf, win }
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

local function collect_expanded_paths(node, out)
  if not node or not node.children then return end
  for _, child in ipairs(node.children) do
    if child.type == 'directory' and child.expanded then
      out[child.abs_path] = true
      collect_expanded_paths(child, out)
    end
  end
end

local function buf_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function reconcile_now(session)
  return model_mod.reconcile(session, buf_lines(session.buf))
end

local function refresh(session)
  te_render.refresh(session, session.buf)
end

-- Anchoring info for deleted entries; shared with render's diff signs.
local deleted_entries = model_mod.deleted_entries

local function id_order_insert_after(session, after_id, ids)
  local pos
  for k, oid in ipairs(session.id_order) do
    if oid == after_id then pos = k break end
  end
  if pos then
    for k = #ids, 1, -1 do
      table.insert(session.id_order, pos + 1, ids[k])
    end
  else
    vim.list_extend(session.id_order, ids)
  end
end

local function remove_children_lines(session, buf, line_nr, depth)
  local rest = vim.api.nvim_buf_get_lines(buf, line_nr, -1, false)
  local removed = 0
  local removed_ids = {}
  for _, l in ipairs(rest) do
    if l ~= '' and l:match('%S') then
      local lid, _, d = parse_line(l)
      if d <= depth then break end
      if lid then removed_ids[lid] = true end
    end
    removed = removed + 1
  end
  if removed > 0 then
    vim.api.nvim_buf_set_lines(buf, line_nr, line_nr + removed, false, {})
  end
  return removed_ids
end

local function prune_id_order(session, removed_ids)
  if not next(removed_ids) then return end
  local surviving = {}
  for _, l in ipairs(buf_lines(session.buf)) do
    local lid = parse_line(l)
    if lid then surviving[lid] = true end
  end
  local new_order = {}
  for _, oid in ipairs(session.id_order) do
    if not removed_ids[oid] or surviving[oid] then
      new_order[#new_order + 1] = oid
    end
  end
  session.id_order = new_order
end

local function on_enter(session)
  local was_modified = vim.bo[session.buf].modified
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local rec = reconcile_now(session)
  local elem = rec.by_line[line_nr]
  if not elem then return end
  local line = vim.api.nvim_buf_get_lines(session.buf, line_nr - 1, line_nr, false)[1]
  local _, _, depth = parse_line(line or '')

  -- yy+p duplicate of a dir line: mint a persistent copy node so this line
  -- gets its own identity/expansion state, then fall through to expand it.
  if elem.kind == 'copy' and not elem.id and elem.type == 'directory' then
    local src = session.nodes[elem.src_id]
    if not src then return end
    local node = model_mod.mint_copy(session, src, elem.name)
    local indent = line:match('^(%s*)') or ''
    vim.api.nvim_buf_set_lines(session.buf, line_nr - 1, line_nr, false,
      { format_line(indent, node.id, node.name .. '/') })
    id_order_insert_after(session, elem.src_id, { node.id })
    rec = reconcile_now(session)
    elem = rec.by_line[line_nr]
    if not elem then return end
  end

  if elem.type == 'directory' and elem.id and (elem.kind == 'entity' or elem.kind == 'copy') then
    if elem.expanded then
      elem.expanded = false
      local removed_ids = remove_children_lines(session, session.buf, line_nr, depth)
      prune_id_order(session, removed_ids)
    else
      elem.expanded = true
      model_mod.ensure_loaded(session, elem)
      local child_lines, new_ids = model_mod.render_children_lines(session, elem, depth + 1)
      if #child_lines > 0 then
        vim.api.nvim_buf_set_lines(session.buf, line_nr, line_nr, false, child_lines)
        id_order_insert_after(session, elem.id, new_ids)
      end
    end
    local pending = refresh(session)
    vim.bo[session.buf].modified = was_modified or pending
  elseif elem.type ~= 'directory' then
    if elem.kind == 'entity' and session.disk[elem.id] then
      win_mod.open_file(session.disk[elem.id].path)
    elseif elem.kind == 'copy' then
      local dk = elem.origin and session.disk[elem.origin]
      if dk then win_mod.open_file(dk.path) end
    end
  end
end

local function post_save_reset(session, acts)
  local expanded = model_mod.expanded_paths(session)
  local function expand_ancestors(p)
    pu.iter_ancestors(p, session.root_dir, function(parent)
      expanded[parent] = true
    end)
  end
  for _, a in ipairs(acts) do
    if a.name == 'create' then
      local dst = a.dst
      if vim.endswith(dst, '/') then
        local d = pu.strip_slash(dst)
        expanded[d] = true
        expand_ancestors(d)
      else
        expand_ancestors(dst)
      end
    elseif a.name == 'move' or a.name == 'copy' then
      if a.dst then expand_ancestors(pu.strip_slash(a.dst)) end
    end
  end
  model_mod.rebuild(session, expanded)
  local lines = model_mod.render_all(session)
  vim.api.nvim_buf_set_lines(session.buf, 0, -1, false, lines)
  refresh(session)
  vim.bo[session.buf].modified = false
end

local function mutate(session)
  if not vim.bo[session.buf].modified then return end

  reconcile_now(session)
  local dupes = model_mod.check_dupes(session)
  local acts = model_mod.diff(session)

  if #acts == 0 and #dupes == 0 then
    vim.bo[session.buf].modified = false
    return
  end

  actions_mod.add_implicit_creates(acts, session.root_dir)

  confirm.show(acts, dupes, session.root_dir, function(confirmed)
    if not confirmed then return end
    actions_mod.execute_actions(acts)
    post_save_reset(session, acts)

    local sidebar_state = require('lu5je0.ext.sidebar.state')
    if sidebar_state:is_open() then
      local ok, files = pcall(require, 'lu5je0.ext.sidebar.sources.files')
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
  local state = require('lu5je0.ext.sidebar.state')
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
      local win = vim.api.nvim_get_current_win()
      vim.wo[win].concealcursor = 'nvic'
      vim.wo[win].conceallevel = 3
      vim.wo[win].number = true
      vim.wo[win].signcolumn = 'yes:1'
      s.win = win
      vim.cmd([[syn match FsEditStoreID /^\s*\zs\/\d\+\s/ conceal]])
      refresh(s)
      return
    end
  end

  local session = model_mod.new(root_dir)

  local seed = {}
  if state.files and state.files.root then
    local sidebar_node = find_sidebar_node(state.files.root, root_dir)
    if sidebar_node then
      collect_expanded_paths(sidebar_node, seed)
    end
  end
  model_mod.rebuild(session, seed)
  local lines = model_mod.render_all(session)

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
    icon = '',
    icon_hl = 'Directory'
  }

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  refresh(session)
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

  vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete' }, {
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
          refresh(session)
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

  local function is_expanded_at(row)
    local rec = reconcile_now(session)
    local elem = rec.by_line[row]
    return elem ~= nil and elem.type == 'directory' and elem.expanded == true
  end

  local function smart_paste(put_cmd)
    local cur_line = vim.api.nvim_get_current_line()
    local _, _, cur_depth, cur_is_dir = parse_line(cur_line)
    local cur_row = vim.api.nvim_win_get_cursor(0)[1]
    local target_depth = (cur_is_dir and is_expanded_at(cur_row)) and (cur_depth + 1) or cur_depth

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
    if vim.fn.mode():sub(1, 1) ~= 'n' then return end
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

    vim.cmd('normal! ' .. vim.v.count1 .. dir)

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
    local rec = reconcile_now(session)
    local acts, reachable = model_mod.diff(session)
    local elem = rec.by_line[row]
    local scope = elem and elem.wpath
    local is_dir = elem and elem.type == 'directory'

    local content = {}
    local function add(prefix, p)
      content[#content + 1] = prefix .. ' ' .. pu.rel(session.root_dir, p)
    end

    for _, a in ipairs(acts) do
      local s = a.src and pu.strip_slash(a.src)
      local d = a.dst and pu.strip_slash(a.dst)
      local hits
      if not scope then
        hits = false
      elseif is_dir then
        hits = (s and pu.inside(s, scope)) or (d and pu.inside(d, scope))
      else
        hits = (s == pu.strip_slash(scope)) or (d == pu.strip_slash(scope))
      end
      if hits then
        if a.name == 'create' then
          add('+', a.dst)
        elseif a.name == 'delete' then
          add('-', a.src)
        elseif a.name == 'move' then
          add('-', a.src)
          add('+', a.dst)
        elseif a.name == 'copy' then
          add('*', a.src)
          add('+', a.dst)
        end
      end
    end

    for _, del in ipairs(deleted_entries(session, rec, reachable)) do
      if del.row == row then
        add('-', del.path)
      end
    end

    if #content == 0 then
      vim.notify('No change at cursor', vim.log.levels.INFO)
      return
    end

    local pbuf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, content)
    vim.bo[pbuf].filetype = 'diff'
    vim.bo[pbuf].modifiable = false
    local w = 0
    for _, l in ipairs(content) do
      w = math.max(w, vim.fn.strdisplaywidth(l))
    end
    w = math.min(math.max(w + 2, 20), vim.o.columns - 4)
    local h = math.min(#content, math.max(1, vim.o.lines - 6))
    vim.api.nvim_open_win(pbuf, false, {
      relative = 'cursor', row = 1, col = 0,
      width = w, height = h,
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
    local all_lines = buf_lines(buf)
    local rec = reconcile_now(session)
    local acts, reachable = model_mod.diff(session)
    local cursor_elem = rec.by_line[cursor_row]

    -- collapsed entity dir with a stash: reset the stash to disk state
    -- (rescan re-claims tracked ids; clearing would read as deletions)
    if cursor_elem and cursor_elem.kind == 'entity' and cursor_elem.type == 'directory'
      and not cursor_elem.expanded and cursor_elem.loaded then
      model_mod.scan_children(session, cursor_elem)
      refresh(session)
      return
    end

    -- cursor on/inside an expanded copy dir: undo the expansion entirely
    do
      local function copy_dir_at(row)
        local e = rec.by_line[row]
        return (e and e.kind == 'copy' and e.id and e.type == 'directory' and e.expanded)
          and e or nil
      end
      local target_row
      if copy_dir_at(cursor_row) then
        target_row = cursor_row
      else
        local _, _, cursor_depth = parse_line(all_lines[cursor_row] or '')
        for j = cursor_row - 1, 1, -1 do
          local l = all_lines[j]
          if l and l:match('%S') then
            local _, _, pd = parse_line(l)
            if pd < cursor_depth then
              if copy_dir_at(j) then target_row = j end
              if pd == 0 then break end
              cursor_depth = pd
            end
          end
        end
      end
      if target_row then
        local cnode = rec.by_line[target_row]
        local _, _, pd = parse_line(all_lines[target_row])
        cnode.expanded = false
        cnode.loaded = false
        cnode.children = {}
        local removed_ids = remove_children_lines(session, buf, target_row, pd)
        prune_id_order(session, removed_ids)
        refresh(session)
        return
      end
    end

    local dupes = model_mod.check_dupes(session)
    if #acts == 0 and #dupes == 0 then
      vim.notify('No change at cursor', vim.log.levels.INFO)
      return
    end

    -- changed line set: renamed/displaced entities, creates, copies, dupes
    local changed_set = {}
    for lnum, elem in pairs(rec.by_line) do
      if elem.kind == 'entity' then
        local dk = session.disk[elem.id]
        if dk and elem.wpath and elem.wpath ~= dk.path then
          changed_set[lnum] = true
        end
      elseif elem.kind ~= 'ghost' then
        changed_set[lnum] = true
      end
    end
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

    local deleted_to_restore = {}
    for _, del in ipairs(deleted_entries(session, rec, reachable)) do
      if del.row == cursor_row then
        deleted_to_restore[#deleted_to_restore + 1] = del
      end
    end

    if not changed_set[cursor_row] and #deleted_to_restore == 0 then
      vim.notify('No change at cursor', vim.log.levels.INFO)
      return
    end

    local function original_line(id)
      local dk = session.disk[id]
      if not dk then return nil end
      local rel = dk.path:sub(#session.root_dir + 2)
      local orig_depth = 0
      for _ in rel:gmatch('/') do orig_depth = orig_depth + 1 end
      local indent = string.rep('  ', orig_depth)
      local restored = dk.type == 'directory' and (dk.name .. '/') or dk.name
      return format_line(indent, id, restored)
    end

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

      for i = hunk_end, hunk_start, -1 do
        local id = parse_line(all_lines[i])
        if not id then
          vim.api.nvim_buf_set_lines(buf, i - 1, i, false, {})
        elseif ids_before_hunk[id] then
          vim.api.nvim_buf_set_lines(buf, i - 1, i, false, {})
        else
          local restored = session.disk[id] and session.disk[id].tracked and original_line(id)
          if restored then
            vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { restored })
          else
            vim.api.nvim_buf_set_lines(buf, i - 1, i, false, {})
          end
          ids_before_hunk[id] = true
        end
      end
    end

    if #deleted_to_restore > 0 then
      for _, del in ipairs(deleted_to_restore) do
        local restored = original_line(del.id)
        if restored then
          vim.api.nvim_buf_set_lines(buf, cursor_row, cursor_row, false, { restored })
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
    local _, _, cur_depth, cur_is_dir = parse_line(cur_line)
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local target_depth = (direction == 'o' and cur_is_dir and is_expanded_at(row))
      and (cur_depth + 1) or cur_depth
    local indent = string.rep('  ', target_depth)
    local placeholder = fmt.PLACEHOLDER

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

  vim.keymap.set('n', 'K', function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local rec = reconcile_now(session)
    model_mod.diff(session) -- annotate wpath
    local elem = rec.by_line[row]
    if elem and elem.wpath then
      require('lu5je0.ext.sidebar.sources.files.info').show_for_path(elem.wpath, { win = 0, buf = buf, line = row })
    end
  end, { buffer = buf, nowait = true })

  vim.api.nvim_create_autocmd('BufReadCmd', {
    buffer = buf,
    callback = function()
      if vim.bo[buf].modified then
        local choice = vim.fn.confirm('Discard unsaved changes and refresh?', '&Yes\n&No', 2)
        if choice ~= 1 then return end
      end
      -- keep expanded dirs by their disk paths (pending renames discarded)
      local expanded = {}
      for id, n in pairs(session.nodes) do
        if n.kind == 'entity' and n.type == 'directory' and n.expanded and session.disk[id] then
          expanded[session.disk[id].path] = true
        end
      end
      model_mod.rebuild(session, expanded)
      local lines = model_mod.render_all(session)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      refresh(session)
      vim.cmd([[syn match FsEditStoreID /^\s*\zs\/\d\+\s/ conceal]])
      vim.bo[buf].modified = false
    end,
  })

  vim.keymap.set('n', '<CR>', function() on_enter(session) end, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'q', quit_with_check, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<leader>q', close_buf, { buffer = buf, nowait = true })
end

function M.open_dir(dir_path, opts)
  opts = opts or {}
  dir_path = vim.fn.fnamemodify(dir_path, ':p'):gsub('/$', '')
  local replace = opts.replace
  if replace == nil then replace = true end
  M.open({ type = 'directory', abs_path = dir_path }, { replace = replace, inplace = opts.inplace })
end

M._parse_line = parse_line
M._sessions = sessions

return M
