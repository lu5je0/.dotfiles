local tree = require('lu5je0.ext.sidebar.sources.files.tree')
local win_mod = require('lu5je0.ext.sidebar.window')
local actions_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions')
local session_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.session')
local te_render = require('lu5je0.ext.sidebar.sources.files.fs-edit.render')
local confirm = require('lu5je0.ext.sidebar.sources.files.fs-edit.confirm')
local pu = require('lu5je0.ext.sidebar.sources.files.fs-edit.path_util')

local LINE_FMT = session_mod.LINE_FMT
local format_line = session_mod.format_line

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

local register_entry = session_mod.register_entry

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
      lines[#lines + 1] = format_line(indent, id, name)
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
      lines[#lines + 1] = format_line(indent, id, name)
      new_ids[#new_ids + 1] = id
      if expanded then
        walk(entry.abs_path, d + 1)
      end
    end
  end

  walk(dir_path, depth)
  return lines, new_ids
end

-- Side-effect-free twin of render_children for the collapse-time cache-vs-disk
-- comparison. Registering ids here would poison id_to_path with entries the
-- user never saw (compute_actions would then emit DELETE for them on save).
-- Returns nil when an entry has no registered id (disk changed externally);
-- callers must treat nil as "cache differs from disk".
local function scan_children_lines(session, dir_path, depth)
  local lines = {}
  local function walk(path, d)
    local entries = tree.scan_dir(path)
    for _, entry in ipairs(entries) do
      local id = session.path_to_id[entry.abs_path]
      if not id then return false end
      local name = entry.name
      local expanded = entry.type == 'directory' and session.expanded_dirs[entry.abs_path]
      if entry.type == 'directory' then
        name = name .. '/'
      end
      lines[#lines + 1] = format_line(string.rep('  ', d), id, name)
      if expanded and not walk(entry.abs_path, d + 1) then
        return false
      end
    end
    return true
  end
  if not walk(dir_path, depth) then return nil end
  return lines
end

local function remove_children_lines(session, buf, line_nr, depth)
  local rest = vim.api.nvim_buf_get_lines(buf, line_nr, -1, false)
  local removed = 0
  for _, l in ipairs(rest) do
    if l ~= '' and l:match('%S') then
      local _, _, d = parse_line(l)
      if d <= depth then break end
    end
    removed = removed + 1
  end
  if removed > 0 then
    vim.api.nvim_buf_set_lines(buf, line_nr, line_nr + removed, false, {})
  end
end

-- returns the effective on-disk path for the entry at line_nr (respecting
-- any parent renames present in the buffer above).
local function current_path_for_line(session, buf, line_nr)
  return pu.current_path(session, buf, line_nr)
end

local function count_id_in_lines(lines, target_id)
  local n = 0
  for _, l in ipairs(lines) do
    if parse_line(l) == target_id then n = n + 1 end
  end
  return n
end

local function count_id_in_buf(session, buf, target_id)
  return count_id_in_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false), target_id)
end

local function render_phantom_children(session, disk_dir, target_dir, depth, is_copy)
  local lines = {}
  local new_ids = {}

  local function walk(disk_path, tgt_path, d)
    local entries = tree.scan_dir(disk_path)
    for _, entry in ipairs(entries) do
      local child_disk = entry.abs_path
      if child_disk == disk_dir then goto continue end
      local child_tgt = tgt_path .. '/' .. entry.name
      local id
      if is_copy then
        id = session_mod.alloc_phantom(session, child_tgt, entry.name, entry.type, child_disk)
      else
        -- displaced rename: reuse original id keyed by disk path
        id = register_entry(session, child_disk, entry.name, entry.type)
        session.id_to_path[id] = child_disk
      end
      local indent = string.rep('  ', d)
      local name = entry.name
      if entry.type == 'directory' then
        name = name .. '/'
      end
      lines[#lines + 1] = format_line(indent, id, name)
      new_ids[#new_ids + 1] = id
      ::continue::
    end
  end

  walk(disk_dir, target_dir, depth)
  return lines, new_ids
end

-- yy+p copy: when a directory id occurs more than once in the buffer, give
-- *this* line a fresh phantom id so its expansion state is independent from
-- the original (the first occurrence keeps the original id). Also snapshots
-- the origin's currently-expanded subtree into copy_snapshot, keyed by the
-- new phantom ids, so expanding the copy reproduces the edited structure.
-- Returns the (possibly re-assigned) id and line.
local function reid_duplicate_dir(session, line_nr, line, id)
  local all_lines = vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)
  if count_id_in_lines(all_lines, id) <= 1 then return id, line end
  local orig_id = id
  local first_line_nr
  for j, l in ipairs(all_lines) do
    if parse_line(l) == id then
      first_line_nr = j
      break
    end
  end
  if not first_line_nr or first_line_nr == line_nr then return id, line end

  local origin_abs = session.store[id].abs_path
  local origin_shadow = session.copy_shadow[id] or origin_abs
  local cur_path = current_path_for_line(session, session.buf, line_nr) or origin_abs
  -- extract current name from the buffer line (user may have renamed it)
  local _, cur_name_with_slash = parse_line(line)
  local raw_name = cur_name_with_slash:sub(1, -2) -- strip trailing '/'
  local new_id = session_mod.alloc_phantom(session, cur_path, raw_name, 'directory', origin_shadow)
  local indent = line:match('^(%s*)') or ''
  local new_line = format_line(indent, new_id, raw_name .. '/')
  vim.api.nvim_buf_set_lines(session.buf, line_nr - 1, line_nr, false, { new_line })
  all_lines[line_nr] = new_line
  if session.id_order then
    local inserted = false
    for i, oid in ipairs(session.id_order) do
      if oid == id and not inserted then
        table.insert(session.id_order, i + 1, new_id)
        inserted = true
        break
      end
    end
    if not inserted then
      session.id_order[#session.id_order + 1] = new_id
    end
  end

  -- Snapshot origin's currently-expanded subtree, preserving its expansion
  -- structure: each level is stored keyed by the new phantom id of that
  -- directory, so expanding only inserts that directory's direct children.
  local origin_line = all_lines[first_line_nr]
  local _, _, origin_depth = parse_line(origin_line or '')
  local snapshot_lines = {}
  local skip_depth = nil
  for j = first_line_nr + 1, #all_lines do
    local l = all_lines[j]
    if not l or l == '' or not l:match('%S') then break end
    local cid, _, d = parse_line(l)
    if d <= origin_depth then break end
    if skip_depth and d > skip_depth then
      -- inside a self-reference subtree, skip
    else
      skip_depth = nil
      if cid and cid == orig_id then
        skip_depth = d
      elseif cid and session.copy_shadow[cid] and session.copy_shadow[cid] == origin_shadow
        and session.store[cid] and session.store[cid].type == 'directory' then
        skip_depth = d
      else
        snapshot_lines[#snapshot_lines + 1] = { line = l, depth = d }
      end
    end
  end
  if #snapshot_lines > 0 then
    session.copy_snapshot = session.copy_snapshot or {}
    local origin_target = current_path_for_line(session, session.buf, first_line_nr) or origin_abs
    -- stack[i] = { depth, target, shadow, dir_new_id, indent_len, direct_children (list of lines) }
    local stack = {
      { depth = origin_depth, target = origin_target, shadow = origin_shadow,
        dir_new_id = new_id, indent_len = indent:len(), direct_children = {} }
    }
    for _, entry in ipairs(snapshot_lines) do
      local cid, cname, d = parse_line(entry.line)
      -- pop stacks deeper than this entry's parent
      while #stack > 0 and stack[#stack].depth >= d do
        local finished = table.remove(stack)
        if #finished.direct_children > 0 then
          session.copy_snapshot[finished.dir_new_id] = finished.direct_children
        end
      end
      local parent = stack[#stack]
      local parent_target = parent.target
      local parent_shadow = parent.shadow
      local parent_indent_len = parent.indent_len
      local raw = (cname:sub(-1) == '/') and cname:sub(1, -2) or cname
      local child_target = parent_target .. '/' .. raw
      local child_shadow
      if cid and session.copy_shadow[cid] then
        child_shadow = session.copy_shadow[cid]
      elseif cid and session.store[cid] then
        child_shadow = session.store[cid].abs_path
      else
        child_shadow = parent_shadow .. '/' .. raw
      end
      local is_dir_c = (cname:sub(-1) == '/')
      local ctype = is_dir_c and 'directory' or 'file'
      local nid = session_mod.alloc_phantom(session, child_target, raw, ctype, child_shadow)
      local child_indent_len = parent_indent_len + 2
      local child_indent = string.rep(' ', child_indent_len)
      local cline = format_line(child_indent, nid, raw .. (is_dir_c and '/' or ''))
      parent.direct_children[#parent.direct_children + 1] = cline
      if is_dir_c then
        stack[#stack + 1] = {
          depth = d, target = child_target, shadow = child_shadow,
          dir_new_id = nid, indent_len = child_indent_len, direct_children = {},
        }
      end
    end
    while #stack > 0 do
      local finished = table.remove(stack)
      if #finished.direct_children > 0 then
        session.copy_snapshot[finished.dir_new_id] = finished.direct_children
      end
    end
  end

  return new_id, new_line
end

local function collapse_dir(session, line_nr, depth, id, abs, current_path)
  actions_mod.set_collapsed(session, id, current_path)
  local all_lines = vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)
  local removed_ids = {}
  local child_lines_cache = {}
  for j = line_nr + 1, #all_lines do
    local l = all_lines[j]
    if l ~= '' and l:match('%S') then
      local _, _, d = parse_line(l)
      if d <= depth then break end
      child_lines_cache[#child_lines_cache + 1] = l
      local cid = l:match('/(%d+) ')
      if cid then removed_ids[tonumber(cid)] = true end
    end
  end
  if #child_lines_cache > 0 then
    -- saved_children_key: abs_path for real dirs (even displaced ones),
    -- shadow#id for phantoms. All lookups go through the same helper.
    local cache_key = actions_mod.saved_children_key(session, id)
    session.saved_children[cache_key] = child_lines_cache
    -- scan_children_lines is a dry-run: nil means disk has entries we never
    -- registered (external change), which counts as a mismatch.
    local disk_lines = scan_children_lines(session, abs, depth + 1)
    local match_disk = disk_lines ~= nil and #disk_lines == #child_lines_cache
    if match_disk then
      for k = 1, #disk_lines do
        if disk_lines[k] ~= child_lines_cache[k] then
          match_disk = false
          break
        end
      end
    end
    if match_disk then
      session.saved_children_clean[cache_key] = true
    else
      session.saved_children_clean[cache_key] = nil
    end
  end
  remove_children_lines(session, session.buf, line_nr, depth)
  if session.id_order and next(removed_ids) then
    local surviving_ids = {}
    for _, l in ipairs(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)) do
      local lid = parse_line(l)
      if lid then surviving_ids[lid] = true end
    end
    local new_order = {}
    for _, oid in ipairs(session.id_order) do
      if not removed_ids[oid] or surviving_ids[oid] then
        new_order[#new_order + 1] = oid
      end
    end
    session.id_order = new_order
  end
end

local function expand_dir(session, line_nr, depth, id, abs, displaced, current_path, shadow_src)
  actions_mod.set_expanded(session, id, current_path)
  local function ids_from_lines(lines)
    local ids = {}
    for _, l in ipairs(lines) do
      local cid = l:match('/(%d+) ')
      if cid then ids[#ids + 1] = tonumber(cid) end
    end
    return ids
  end
  local child_lines, new_ids
  local cache_key = actions_mod.saved_children_key(session, id)
  local cached = session.saved_children[cache_key]
  if cached then
    child_lines = cached
    session.saved_children[cache_key] = nil
    session.saved_children_clean[cache_key] = nil
    new_ids = ids_from_lines(child_lines)
  elseif shadow_src and session.copy_snapshot and session.copy_snapshot[id] then
    child_lines = session.copy_snapshot[id]
    session.copy_snapshot[id] = nil
    new_ids = ids_from_lines(child_lines)
  elseif shadow_src then
    child_lines, new_ids = render_phantom_children(session, shadow_src, abs, depth + 1, true)
  elseif displaced then
    local is_copy = count_id_in_buf(session, session.buf, id) > 1
    child_lines, new_ids = render_phantom_children(session, abs, current_path, depth + 1, is_copy)
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
end

local function on_enter(session)
  local was_modified = vim.bo[session.buf].modified
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(session.buf, line_nr - 1, line_nr, false)[1]
  local id, _, depth, is_dir = parse_line(line)

  if is_dir and id and session.store[id] and session.store[id].type == 'directory' then
    id, line = reid_duplicate_dir(session, line_nr, line, id)
  end

  if is_dir and id then
    local entry = session.store[id]
    if not entry then return end
    local abs = entry.abs_path
    local displaced = pu.is_displaced(session, session.buf, line_nr)
    local current_path = displaced and current_path_for_line(session, session.buf, line_nr) or abs
    local shadow_src = session.copy_shadow[id]
    -- A renamed dir may still carry a stale expansion entry under its original
    -- abs path (renamed while expanded); is_expanded checks both keys so <CR>
    -- collapses instead of duplicating children below.
    if actions_mod.is_expanded(session, id, current_path) then
      collapse_dir(session, line_nr, depth, id, abs, current_path)
    else
      expand_dir(session, line_nr, depth, id, abs, displaced, current_path, shadow_src)
    end
    refresh_decorations(session, session.buf)
    refresh_diff_signs(session, session.buf)
    local eff = actions_mod.effective_buf_lines(
      session, vim.api.nvim_buf_get_lines(session.buf, 0, -1, false))
    vim.bo[session.buf].modified = was_modified
      or actions_mod.has_dirty_saved_children(session, eff)
      or actions_mod.has_active_phantom(session, eff)
  elseif id and not is_dir then
    local entry = session.store[id]
    if entry then
      win_mod.open_file(entry.abs_path)
    end
  end
end

local function mutate(session)
  if not vim.bo[session.buf].modified then return end

  local buf_lines = actions_mod.effective_buf_lines(
    session, vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)
  )

  if vim.g.fs_edit_debug then
    local seen = {}
    for _, l in ipairs(buf_lines) do
      local lid = parse_line(l)
      if lid then seen[lid] = true end
    end
    for id, _ in pairs(session.id_to_path) do
      if session.store[id] and not (session.copy_shadow and session.copy_shadow[id])
        and not seen[id] then
        local visible_row
        local raw = vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)
        for i, l in ipairs(raw) do
          if parse_line(l) == id then visible_row = i; break end
        end
        if visible_row then
          vim.notify(('fs-edit invariant: id %d visible in buffer but dropped by effective_buf_lines'):format(id), vim.log.levels.WARN)
        end
      end
    end
  end

  local dupes = check_duplicates(session, buf_lines)
  local actions = compute_actions(session, buf_lines)

  if #actions == 0 and #dupes == 0 then
    if not actions_mod.has_dirty_saved_children(session, buf_lines)
      and not actions_mod.has_active_phantom(session, buf_lines) then
      vim.bo[session.buf].modified = false
    end
    return
  end

  actions_mod.add_implicit_creates(actions, session.root_dir)

  confirm.show(actions, dupes, session.root_dir, function(confirmed)
    if not confirmed then return end

    execute_actions(actions)

    local function expand_ancestors(p)
      pu.iter_ancestors(p, session.root_dir, function(parent)
        session.expanded_dirs[parent] = true
      end)
    end
    for _, a in ipairs(actions) do
      if a.name == 'create' then
        local dst = a.dst
        if vim.endswith(dst, '/') then
          local d = pu.strip_slash(dst)
          session.expanded_dirs[d] = true
          expand_ancestors(d)
        else
          expand_ancestors(dst)
        end
      elseif a.name == 'move' or a.name == 'copy' then
        if a.dst then
          expand_ancestors(pu.strip_slash(a.dst))
        end
      end
    end

    session_mod.reset(session)

    local lines = render_to_lines(session)
    vim.api.nvim_buf_set_lines(session.buf, 0, -1, false, lines)
    refresh_decorations(session, session.buf)
    vim.bo[session.buf].modified = false

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
      te_render.refresh_decorations(s, b)
      return
    end
  end

  local session = session_mod.new(root_dir)

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
    local cur_row = vim.api.nvim_win_get_cursor(0)[1]
    local is_expanded = cur_is_dir and pu.is_expanded_at(session, buf, cur_row) or false
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
    local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local line = all_lines[row]
    if not line then return end

    local scope, is_dir
    do
      local i = 0
      for entry in actions_mod.iter_lines(session, all_lines) do
        i = i + 1
        if i == row then
          scope = entry.current_path
          is_dir = entry.is_dir
          break
        end
      end
    end

    -- recompute actions from current buffer
    local buf_lines = actions_mod.effective_buf_lines(session, all_lines)
    local actions = compute_actions(session, buf_lines)

    local content = {}
    local function add(prefix, p)
      content[#content + 1] = prefix .. ' ' .. pu.rel(session.root_dir, p)
    end

    for _, a in ipairs(actions) do
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

    -- handle deletion signs anchored on neighbor rows (cursor is on the neighbor)
    if session.id_order then
      local seen_ids = {}
      local id_to_buflines_idx = {}
      for i, l in ipairs(buf_lines) do
        local lid = parse_line(l)
        if lid then
          seen_ids[lid] = true
          id_to_buflines_idx[lid] = i
        end
      end
      -- buf_lines was produced by effective_buf_lines and may contain rows
      -- spliced in from saved_children; line_map translates an effective index
      -- back to a 1-based visible row (-1 = spliced, no real row).
      local _, line_map = actions_mod.effective_buf_lines_mapped(session, all_lines)
      local function row_of(idx)
        if not idx then return nil end
        if line_map[idx] and line_map[idx] >= 0 then return line_map[idx] + 1 end
        for k = idx + 1, #buf_lines do
          if line_map[k] and line_map[k] >= 0 then return line_map[k] + 1 end
        end
        for k = idx - 1, 1, -1 do
          if line_map[k] and line_map[k] >= 0 then return line_map[k] + 1 end
        end
        return nil
      end
      for idx, oid in ipairs(session.id_order) do
        if session.id_to_path[oid] and not seen_ids[oid] then
          local target_idx
          for k = idx - 1, 1, -1 do
            local prev = id_to_buflines_idx[session.id_order[k]]
            if prev then target_idx = prev; break end
          end
          if not target_idx then
            for k = idx + 1, #session.id_order do
              local nxt = id_to_buflines_idx[session.id_order[k]]
              if nxt then target_idx = nxt; break end
            end
          end
          local target_row = row_of(target_idx) or 1
          if target_row == row then
            add('-', session.id_to_path[oid])
          end
        end
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
    local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    local cursor_line = all_lines[cursor_row]
    if cursor_line then
      local cid, _, _, cis_dir = parse_line(cursor_line)
      if cis_dir and cid and session.store[cid] and not session.copy_shadow[cid] then
        local cabs = session.store[cid].abs_path
        local cache_key = actions_mod.saved_children_key(session, cid)
        if not actions_mod.is_expanded(session, cid) and session.saved_children[cache_key] then
          local _, _, cdepth = parse_line(cursor_line)
          local disk_lines = render_children(session, cabs, cdepth + 1)
          if #disk_lines > 0 then
            session.saved_children[cache_key] = disk_lines
            session.saved_children_clean[cache_key] = true
          else
            session.saved_children[cache_key] = nil
            session.saved_children_clean[cache_key] = nil
          end
          refresh_decorations(session, buf)
          refresh_diff_signs(session, buf)
          return
        end
      end
    end

    -- If cursor is on or inside an expanded phantom dir, collapse it (undo expand).
    do
      local _, _, cursor_depth = parse_line(cursor_line or '')
      local phantom_dir_row, phantom_dir_depth
      -- check cursor line itself
      if cursor_line then
        local cid, _, _, cis_dir = parse_line(cursor_line)
        if cis_dir and cid and session.copy_shadow[cid] and actions_mod.is_expanded(session, cid) then
          phantom_dir_row = cursor_row
          phantom_dir_depth = cursor_depth
        end
      end
      -- search upward for enclosing phantom dir
      if not phantom_dir_row then
        for j = cursor_row - 1, 1, -1 do
          local l = all_lines[j]
          if l and l:match('%S') then
            local pid, _, pd, pis_dir = parse_line(l)
            if pd < cursor_depth then
              if pis_dir and pid and session.copy_shadow[pid] and actions_mod.is_expanded(session, pid) then
                phantom_dir_row = j
                phantom_dir_depth = pd
              end
              if pd == 0 then break end
              cursor_depth = pd
            end
          end
        end
      end
      if phantom_dir_row then
        local pid, _, pd = parse_line(all_lines[phantom_dir_row])
        actions_mod.set_collapsed(session, pid)
        session.saved_children[actions_mod.saved_children_key(session, pid)] = nil
        if session.copy_snapshot then session.copy_snapshot[pid] = nil end
        remove_children_lines(session, buf, phantom_dir_row, pd)
        refresh_decorations(session, buf)
        refresh_diff_signs(session, buf)
        return
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

      local fmt = LINE_FMT
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
      local fmt = LINE_FMT
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
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local is_expanded = cur_is_dir and pu.is_expanded_at(session, buf, row) or false
    local target_depth = (direction == 'o' and cur_is_dir and is_expanded) and (cur_depth + 1) or cur_depth
    local indent = string.rep('  ', target_depth)
    local placeholder = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions').PLACEHOLDER

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
    local path = current_path_for_line(session, buf, row)
    if path then
      require('lu5je0.ext.sidebar.sources.files.info').show_for_path(path, { win = 0, buf = buf, line = row })
    end
  end, { buffer = buf, nowait = true })

  vim.api.nvim_create_autocmd('BufReadCmd', {
    buffer = buf,
    callback = function()
      if vim.bo[buf].modified then
        local choice = vim.fn.confirm('Discard unsaved changes and refresh?', '&Yes\n&No', 2)
        if choice ~= 1 then return end
      end
      session_mod.reset(session)
      local lines = render_to_lines(session)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      refresh_decorations(session, buf)
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
M._compute_actions = compute_actions

return M
