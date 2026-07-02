local tree = require('lu5je0.ext.tree-sidebar.sources.files.tree')
local win_mod = require('lu5je0.ext.tree-sidebar.window')
local actions_mod = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.actions')
local te_render = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.render')
local confirm = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.confirm')
local pu = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.path_util')

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

local function current_path_for_line(session, buf, line_nr)
  -- returns the effective on-disk path for the entry at line_nr (respecting
  -- any parent renames present in the buffer above). Falls back to entry.abs_path
  -- when the id/depth logic can't determine a parent.
  local line = vim.api.nvim_buf_get_lines(buf, line_nr - 1, line_nr, false)[1]
  if not line then return nil end
  local id, name, depth, is_dir = parse_line(line)
  if not id then return nil end
  local parent_path = session.root_dir
  for i = line_nr - 1, 1, -1 do
    local l = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1]
    if l and l:match('%S') then
      local pid, pname, pdepth, pis_dir = parse_line(l)
      if pdepth < depth then
        if pid and session.store[pid] then
          local pcur = current_path_for_line(session, buf, i)
          if pcur then
            parent_path = pcur
          elseif pis_dir then
            parent_path = session.store[pid].abs_path
          end
        elseif pis_dir and pname ~= '' then
          parent_path = parent_path .. '/' .. pname:sub(1, -2)
        end
        break
      end
    end
  end
  local raw_name = is_dir and name:sub(1, -2) or name
  return parent_path .. '/' .. raw_name
end

local function count_id_in_buf(session, buf, target_id)
  local total = vim.api.nvim_buf_line_count(buf)
  local n = 0
  for i = 1, total do
    local l = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1]
    if l then
      local lid = parse_line(l)
      if lid == target_id then n = n + 1 end
    end
  end
  return n
end

local function render_phantom_children(session, disk_dir, target_dir, depth, is_copy)
  local id_width = session._id_width or 1
  local fmt = '%s/%0' .. id_width .. 'd %s'
  local lines = {}
  local new_ids = {}

  local function walk(disk_path, tgt_path, d)
    local entries = tree.scan_dir(disk_path)
    for _, entry in ipairs(entries) do
      local child_disk = entry.abs_path
      local child_tgt = tgt_path .. '/' .. entry.name
      local id
      if is_copy then
        id = session.next_id
        session.next_id = id + 1
        session.store[id] = { name = entry.name, abs_path = child_tgt, type = entry.type }
        session.id_to_path[id] = child_tgt
        session.path_to_id[child_tgt] = id
        session.copy_shadow[id] = child_disk
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
      lines[#lines + 1] = string.format(fmt, indent, id, name)
      new_ids[#new_ids + 1] = id
      -- do not auto-recurse into displaced children by default; expand on demand
    end
  end

  walk(disk_dir, target_dir, depth)
  return lines, new_ids
end

local function on_enter(session)
  local was_modified = vim.bo[session.buf].modified
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(session.buf, line_nr - 1, line_nr, false)[1]
  local id, _, depth, is_dir = parse_line(line)

  -- If a directory id appears multiple times in the buffer (yy+p copy),
  -- reassign a fresh phantom id to *this* line so its expansion state is
  -- independent from the original. Skip the first occurrence (keeps the
  -- original id) and only re-id subsequent copies.
  if is_dir and id and session.store[id] and session.store[id].type == 'directory'
    and count_id_in_buf(session, session.buf, id) > 1 then
    local first_line_nr
    do
      local total = vim.api.nvim_buf_line_count(session.buf)
      for j = 1, total do
        local l = vim.api.nvim_buf_get_lines(session.buf, j - 1, j, false)[1]
        if l and parse_line(l) == id then
          first_line_nr = j
          break
        end
      end
    end
    if first_line_nr and first_line_nr ~= line_nr then
      local origin_abs = session.store[id].abs_path
      local origin_shadow = session.copy_shadow[id] or origin_abs
      local cur_path = current_path_for_line(session, session.buf, line_nr) or origin_abs
      -- extract current name from the buffer line (user may have renamed it)
      local _, cur_name_with_slash = parse_line(line)
      local raw_name = cur_name_with_slash:sub(1, -2) -- strip trailing '/'
      local new_id = session.next_id
      session.next_id = new_id + 1
      session.store[new_id] = { name = raw_name, abs_path = cur_path, type = 'directory' }
      session.id_to_path[new_id] = cur_path
      session.path_to_id[cur_path] = new_id
      session.copy_shadow[new_id] = origin_shadow
      local id_width = session._id_width or 1
      local fmt = '%s/%0' .. id_width .. 'd %s'
      local indent = line:match('^(%s*)') or ''
      local new_line = string.format(fmt, indent, new_id, raw_name .. '/')
      vim.api.nvim_buf_set_lines(session.buf, line_nr - 1, line_nr, false, { new_line })
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
      local origin_line = vim.api.nvim_buf_get_lines(session.buf, first_line_nr - 1, first_line_nr, false)[1]
      local _, _, origin_depth = parse_line(origin_line or '')
      local total = vim.api.nvim_buf_line_count(session.buf)
      local snapshot_lines = {}
      for j = first_line_nr + 1, total do
        local l = vim.api.nvim_buf_get_lines(session.buf, j - 1, j, false)[1]
        if not l or l == '' or not l:match('%S') then break end
        local _, _, d = parse_line(l)
        if d <= origin_depth then break end
        snapshot_lines[#snapshot_lines + 1] = { line = l, depth = d }
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
          local nid = session.next_id
          session.next_id = nid + 1
          session.store[nid] = { name = raw, abs_path = child_target, type = ctype }
          session.id_to_path[nid] = child_target
          session.path_to_id[child_target] = nid
          session.copy_shadow[nid] = child_shadow
          local child_indent_len = parent_indent_len + 2
          local child_indent = string.rep(' ', child_indent_len)
          local cline = string.format(fmt, child_indent, nid, raw .. (is_dir_c and '/' or ''))
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

      id = new_id
      line = new_line
    end
  end

  if is_dir and id then
    local entry = session.store[id]
    if not entry then return end
    local abs = entry.abs_path
    local displaced = pu.is_displaced(session, session.buf, line_nr)
    local current_path = displaced and current_path_for_line(session, session.buf, line_nr) or abs
    local shadow_src = session.copy_shadow[id]
    local expand_key
    if shadow_src then
      expand_key = shadow_src .. '#' .. id
    else
      expand_key = current_path or abs
    end
    if session.expanded_dirs[expand_key] then
      session.expanded_dirs[expand_key] = nil
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
      if #child_lines_cache > 0 and not displaced and not shadow_src then
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
        if not has_diff then
          for _, cl in ipairs(child_lines_cache) do
            local cid, _, _, cis_dir = parse_line(cl)
            if cis_dir and cid and session.store[cid] then
              local cabs = session.store[cid].abs_path
              if session.saved_children[cabs] then
                has_diff = true
                break
              end
            end
          end
        end
        if has_diff then
          session.saved_children[abs] = child_lines_cache
        else
          session.saved_children[abs] = nil
        end
      elseif #child_lines_cache > 0 then
        session.saved_children[expand_key] = child_lines_cache
      else
        session.saved_children[expand_key] = nil
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
      session.expanded_dirs[expand_key] = true
      local child_lines, new_ids
      local cached = session.saved_children[expand_key] or (not displaced and not shadow_src and session.saved_children[abs])
      if cached then
        child_lines = cached
        session.saved_children[expand_key] = nil
        if not shadow_src then session.saved_children[abs] = nil end
        new_ids = {}
        for _, l in ipairs(child_lines) do
          local cid = l:match('/(%d+) ')
          if cid then new_ids[#new_ids + 1] = tonumber(cid) end
        end
      elseif shadow_src and session.copy_snapshot and session.copy_snapshot[id] then
        child_lines = session.copy_snapshot[id]
        session.copy_snapshot[id] = nil
        new_ids = {}
        for _, l in ipairs(child_lines) do
          local cid = l:match('/(%d+) ')
          if cid then new_ids[#new_ids + 1] = tonumber(cid) end
        end
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
      refresh_decorations(session, session.buf)
    end
    vim.bo[session.buf].modified = was_modified or next(session.saved_children) ~= nil or next(session.copy_shadow) ~= nil
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

  local dupes = check_duplicates(session, buf_lines)
  local actions = compute_actions(session, buf_lines)

  if #actions == 0 and #dupes == 0 then
    if next(session.saved_children) == nil and next(session.copy_shadow) == nil then
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

    session.store = {}
    session.next_id = 1
    session.id_to_path = {}
    session.path_to_id = {}
    session.saved_children = {}
    session.copy_shadow = {}
    session.copy_snapshot = {}

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
    copy_shadow = {},
    copy_snapshot = {},
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
      -- build mapping from buf_lines index -> visible row (line_map analogue based on all_lines)
      local raw_idx_to_row = {}
      local ridx = 0
      for vi, vl in ipairs(all_lines) do
        if #vl > 0 then
          ridx = ridx + 1
          raw_idx_to_row[ridx] = vi
        end
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
          local target_row = target_idx and raw_idx_to_row[target_idx] or 1
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
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local is_expanded = cur_is_dir and pu.is_expanded_at(session, buf, row) or false
    local target_depth = (direction == 'o' and cur_is_dir and is_expanded) and (cur_depth + 1) or cur_depth
    local indent = string.rep('  ', target_depth)
    local placeholder = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.actions').PLACEHOLDER

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
      session.copy_shadow = {}
      session.copy_snapshot = {}
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
