local M = {}

M.PLACEHOLDER = '\194\160' -- NBSP (U+00A0). Used by o/O to keep a real char so the cursor lands after the icon.

-- Parse a buffer line. Returns id (or nil), name, depth, is_dir.
function M.parse_line(line)
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
  if not id and vim.startswith(name, M.PLACEHOLDER) then
    name = name:sub(#M.PLACEHOLDER + 1)
  end
  local is_dir = vim.endswith(name, '/')
  return id, name, depth, is_dir
end

-- Expand a buffer's raw lines into the effective list used for action computation:
-- empty lines are dropped and, for any collapsed directory whose line is present,
-- its saved_children are spliced in after the directory line.
function M.effective_buf_lines(session, all_lines)
  local out = {}
  local function expand(lines)
    for _, l in ipairs(lines) do
      if #l > 0 then
        out[#out + 1] = l
        local lid, _, _, lis_dir = M.parse_line(l)
        if lis_dir and lid and session.store[lid] then
          local shadow_src = session.copy_shadow and session.copy_shadow[lid]
          local key
          if shadow_src then
            key = shadow_src .. '#' .. lid
          else
            key = session.store[lid].abs_path
          end
          if not session.expanded_dirs[key] and session.saved_children[key] then
            expand(session.saved_children[key])
          end
        end
      end
    end
  end
  expand(all_lines)
  return out
end

-- Stateful single-pass walker over buf_lines. Each iteration yields:
--   { line, id, name, depth, is_dir, parent_path, current_path }
-- where current_path = parent_path .. '/' .. raw_name (nil for blank-name lines).
-- The depth-based path stack is maintained internally so callers don't need to
-- reimplement it. Stack push rules match compute_actions / refresh_diff_signs:
--   * id + is_dir         -> push current_path
--   * id + dir-in-store   -> push session.store[id].abs_path (collapsed-paste case)
--   * no id + is_dir      -> push current_path
function M.iter_lines(session, buf_lines)
  local stack = { { path = session.root_dir, depth = -1 } }
  local i = 0
  return function()
    i = i + 1
    local line = buf_lines[i]
    if line == nil then return nil end
    local id, name, depth, is_dir = M.parse_line(line)
    while #stack > 1 and stack[#stack].depth >= depth do
      table.remove(stack)
    end
    local parent_path = stack[#stack].path
    local current_path
    if name and name ~= '' then
      local raw_name = is_dir and name:sub(1, -2) or name
      current_path = parent_path .. '/' .. raw_name
    elseif id then
      -- legacy fallback: id'd line with empty name acts as parent_path .. '/'
      current_path = parent_path .. '/'
    end
    if id then
      if is_dir and current_path then
        table.insert(stack, { path = current_path, depth = depth })
      elseif session.store[id] and session.store[id].type == 'directory' then
        table.insert(stack, { path = session.store[id].abs_path, depth = depth })
      end
    elseif is_dir and current_path then
      table.insert(stack, { path = current_path, depth = depth })
    end
    return { line = line, id = id, name = name, depth = depth, is_dir = is_dir,
             parent_path = parent_path, current_path = current_path }
  end
end

function M.compute_actions(session, buf_lines)
  local seen_ids = {}
  local actions = {}
  local transitions = {}

  for entry in M.iter_lines(session, buf_lines) do
    local id, name, depth, is_dir = entry.id, entry.name, entry.depth, entry.is_dir
    local parent_path = entry.parent_path

    if id then
      seen_ids[id] = true
      transitions[id] = transitions[id] or {}
      table.insert(transitions[id], entry.current_path)
    elseif name ~= '' then
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

  -- collect top-level ancestor moves for suppression of redundant child moves
  local ancestor_moves = {} -- non-phantom dir renames
  local copy_shadow = session.copy_shadow or {}

  for id, new_paths in pairs(transitions) do
    local id_in_snapshot = session.id_to_path[id]
    local store_entry = session.store[id]
    if store_entry and store_entry.type == 'directory' and not copy_shadow[id] then
      local old_path = id_in_snapshot or store_entry.abs_path
      local keep_original = vim.tbl_contains(new_paths, old_path)
      local collapsed = not id_in_snapshot
      if not keep_original and not collapsed then
        local last = new_paths[#new_paths]
        if last ~= old_path then
          ancestor_moves[#ancestor_moves + 1] = { old = old_path, new = last }
        end
      end
    end
  end

  -- phantom dir targets and modified-subtree detection
  local phantom_dir_targets = {}
  for id, new_paths in pairs(transitions) do
    if copy_shadow[id] and session.store[id] and session.store[id].type == 'directory' then
      phantom_dir_targets[id] = new_paths[#new_paths]
    end
  end
  local dir_has_child_phantom = {}
  for cid, cnew_paths in pairs(transitions) do
    if copy_shadow[cid] then
      local ctarget = cnew_paths[#cnew_paths]
      for did, dtarget in pairs(phantom_dir_targets) do
        if did ~= cid and vim.startswith(ctarget, dtarget .. '/') then
          dir_has_child_phantom[did] = true
        end
      end
    end
  end
  -- detect phantom dirs that originally had children (even if all deleted from buffer)
  local dir_ever_had_children = {}
  for cid, _ in pairs(copy_shadow) do
    if session.store[cid] then
      local cabs = session.store[cid].abs_path
      for did, dtarget in pairs(phantom_dir_targets) do
        if did ~= cid and vim.startswith(cabs, dtarget .. '/') then
          dir_ever_had_children[did] = true
        end
      end
    end
  end

  local function implied_by_ancestor_move(old_path, new_path)
    for _, am in ipairs(ancestor_moves) do
      if vim.startswith(old_path, am.old .. '/') then
        local suffix = old_path:sub(#am.old + 1)
        if am.new .. suffix == new_path then
          return true
        end
      end
    end
    return false
  end

  local function under_ancestor_move(path)
    for _, am in ipairs(ancestor_moves) do
      if path == am.old or vim.startswith(path, am.old .. '/') then
        return am
      end
    end
    return nil
  end

  for id, path in pairs(session.id_to_path) do
    if not seen_ids[id] then
      if copy_shadow[id] then
        -- phantom: never emit delete for phantom targets
      else
        local am = under_ancestor_move(path)
        if not am then
          table.insert(actions, { name = 'delete', src = path })
        elseif session.expanded_dirs[am.new] or session.expanded_dirs[am.old] then
          local suffix = path:sub(#am.old + 1)
          table.insert(actions, { name = 'delete', src = am.new .. suffix })
        end
      end
    end
  end

  for id, new_paths in pairs(transitions) do
    local shadow_src = copy_shadow[id]
    if shadow_src then
      -- phantom entry: independent of buffer position, always emit copy from shadow
      local target = new_paths[#new_paths]
      local store_entry = session.store[id]
      local is_dir = store_entry and store_entry.type == 'directory'
      if is_dir and (dir_has_child_phantom[id] or dir_ever_had_children[id]) then
        -- subtree was expanded: create dir; surviving children emit their own copies
        table.insert(actions, { name = 'create', dst = target .. '/' })
      else
        -- unmodified subtree or a phantom file: single copy (bulk cp -r for dirs)
        table.insert(actions, { name = 'copy', src = shadow_src, dst = target })
      end
    else
      local id_in_snapshot = session.id_to_path[id]
      local old_path = id_in_snapshot or (session.store[id] and session.store[id].abs_path)
      if old_path then
        local keep_original = vim.tbl_contains(new_paths, old_path)
        local collapsed = not id_in_snapshot and session.store[id] ~= nil
        local multi_relocate = not keep_original and not collapsed and #new_paths > 1
        -- rewrite src if it lives under a renamed ancestor
        local effective_src = old_path
        for _, am in ipairs(ancestor_moves) do
          if vim.startswith(old_path, am.old .. '/') then
            effective_src = am.new .. old_path:sub(#am.old + 1)
            break
          end
        end
        for i, new_path in ipairs(new_paths) do
          if new_path ~= old_path then
            if implied_by_ancestor_move(old_path, new_path) then
              -- parent rename carries this child; skip
            elseif keep_original or collapsed or (multi_relocate and i < #new_paths) then
              table.insert(actions, { name = 'copy', src = effective_src, dst = new_path })
            else
              table.insert(actions, { name = 'move', src = effective_src, dst = new_path })
            end
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

function M.check_duplicates(session, buf_lines)
  local seen_names = {}
  local dupes = {}

  for entry in M.iter_lines(session, buf_lines) do
    if entry.current_path and entry.name ~= '' then
      local key = entry.current_path
      local raw_name = entry.is_dir and entry.name:sub(1, -2) or entry.name
      if seen_names[key] then
        dupes[#dupes + 1] = raw_name
      else
        seen_names[key] = true
      end
    end
  end
  return dupes
end

function M.has_pending_changes(session, visible_lines)
  local buf_lines = M.effective_buf_lines(session, visible_lines)
  local actions = M.compute_actions(session, buf_lines)
  if #actions > 0 then return true end
  local dupes = M.check_duplicates(session, buf_lines)
  if #dupes > 0 then return true end
  if next(session.saved_children) ~= nil then return true end
  if session.copy_shadow and next(session.copy_shadow) ~= nil then return true end
  return false
end

local function has_trash()
  return vim.fn.executable('q-trash') == 1
end
M.has_trash = has_trash

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

function M.add_implicit_creates(actions, root_dir)
  local existing_dirs = { [root_dir] = true }
  for _, a in ipairs(actions) do
    if a.name == 'create' and vim.endswith(a.dst, '/') then
      existing_dirs[a.dst:sub(1, -2)] = true
    end
  end
  local added = {}
  for _, a in ipairs(actions) do
    if (a.name == 'move' or a.name == 'copy') and a.dst then
      local parent = vim.fs.dirname(a.dst)
      while parent and parent ~= root_dir and not existing_dirs[parent] do
        if not vim.uv.fs_stat(parent) then
          added[parent] = true
        end
        existing_dirs[parent] = true
        parent = vim.fs.dirname(parent)
      end
    end
  end
  for dir in pairs(added) do
    table.insert(actions, { name = 'create', dst = dir .. '/' })
  end
end

local function strip_trailing_slash(p)
  if vim.endswith(p, '/') then return p:sub(1, -2) end
  return p
end

local function do_rename(src, dst)
  local ok, err, name = vim.uv.fs_rename(src, dst)
  if ok then return true end
  if name == 'EXDEV' then
    local res = vim.fn.system({ 'cp', '-r', src, dst })
    if vim.v.shell_error ~= 0 then
      return false, res
    end
    vim.fn.delete(src, 'rf')
    return true
  end
  return false, err
end

function M.plan_actions(actions)
  local function strip(p) return strip_trailing_slash(p) end
  local expanded = {}
  do
    local move_by_src = {}
    for _, a in ipairs(actions) do
      if a.name == 'move' and a.src then
        move_by_src[strip(a.src)] = a
      end
    end
    local handled = {}
    for i, a in ipairs(actions) do
      if a.name == 'move' and a.src and not handled[a] then
        local s = strip(a.src)
        local d = strip(a.dst)
        local other = move_by_src[d]
        if other and other ~= a and strip(other.dst) == s and not handled[other] then
          local tmp = s .. '.fs-edit-swap-' .. i
          local stage1 = { name = 'move', src = a.src, dst = tmp }
          local stage2 = { name = 'move', src = tmp, dst = a.dst }
          expanded[#expanded + 1] = stage1
          expanded[#expanded + 1] = other
          expanded[#expanded + 1] = stage2
          stage2._after_action = other
          handled[a] = true
          handled[other] = true
        else
          expanded[#expanded + 1] = a
          handled[a] = true
        end
      elseif not handled[a] then
        expanded[#expanded + 1] = a
        handled[a] = true
      end
    end
  end

  local nodes = {}
  for _, a in ipairs(expanded) do
    local reads, consumes, writes = nil, nil, nil
    if a.name == 'create' then
      writes = strip(a.dst)
    elseif a.name == 'delete' then
      reads = a.src
      consumes = a.src
    elseif a.name == 'move' then
      reads = strip(a.src)
      consumes = strip(a.src)
      writes = strip(a.dst)
    elseif a.name == 'copy' then
      reads = strip(a.src)
      writes = strip(a.dst)
    end
    nodes[#nodes + 1] = { action = a, reads = reads, consumes = consumes, writes = writes }
  end

  local function covers(ancestor, descendant)
    if not ancestor or not descendant then return false end
    return descendant == ancestor or vim.startswith(descendant, ancestor .. '/')
  end
  local function strict_ancestor(ancestor, descendant)
    if not ancestor or not descendant then return false end
    return descendant ~= ancestor and vim.startswith(descendant, ancestor .. '/')
  end

  local n = #nodes
  local indeg = {}
  local edges = {}
  for i = 1, n do indeg[i] = 0; edges[i] = {} end

  local function add_edge(i, j)
    if i == j then return end
    for _, k in ipairs(edges[i]) do if k == j then return end end
    edges[i][#edges[i] + 1] = j
    indeg[j] = indeg[j] + 1
  end

  for i = 1, n do
    for j = 1, n do
      if i ~= j then
        local a, b = nodes[i], nodes[j]
        if a.reads and b.consumes and covers(b.consumes, a.reads) then
          add_edge(i, j)
        end
        if a.writes and b.writes and strict_ancestor(a.writes, b.writes) then
          add_edge(i, j)
        end
        if a.writes and b.reads and strict_ancestor(a.writes, b.reads) then
          add_edge(i, j)
        end
        if a.action.name == 'delete' and b.action.name == 'create'
          and a.consumes and b.writes and a.consumes == b.writes then
          add_edge(i, j)
        end
        if b.action._after_action and a.action == b.action._after_action then
          add_edge(i, j)
        end
      end
    end
  end

  local queue = {}
  for i = 1, n do
    if indeg[i] == 0 then queue[#queue + 1] = i end
  end
  local ordered = {}
  local head = 1
  while head <= #queue do
    local i = queue[head]; head = head + 1
    ordered[#ordered + 1] = nodes[i].action
    for _, j in ipairs(edges[i]) do
      indeg[j] = indeg[j] - 1
      if indeg[j] == 0 then queue[#queue + 1] = j end
    end
  end

  if #ordered ~= n then
    vim.notify('fs-edit: dependency cycle detected, falling back to input order', vim.log.levels.WARN)
    ordered = {}
    for _, node in ipairs(nodes) do ordered[#ordered + 1] = node.action end
  end

  return ordered
end

function M.execute_actions(actions)
  local ordered = M.plan_actions(actions)
  local function strip(p) return strip_trailing_slash(p) end

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
      local src = strip(action.src)
      local dst = strip(action.dst)
      local new_parent = vim.fs.dirname(dst)
      if not vim.uv.fs_stat(new_parent) then
        vim.fn.mkdir(new_parent, 'p')
      end
      local ok, err = do_rename(src, dst)
      if ok then
        rename_bufs(src, dst)
      else
        vim.notify('fs-edit: move failed: ' .. tostring(err), vim.log.levels.ERROR)
      end
    elseif action.name == 'copy' then
      local src = strip(action.src)
      local dst = strip(action.dst)
      local new_parent = vim.fs.dirname(dst)
      if not vim.uv.fs_stat(new_parent) then
        vim.fn.mkdir(new_parent, 'p')
      end
      vim.fn.system({ 'cp', '-r', src, dst })
    end
  end
end

function M.format_action(action, root_dir)
  local function rel(path)
    if vim.startswith(path, root_dir .. '/') then
      return path:sub(#root_dir + 2)
    end
    return path
  end
  local label, detail
  if action.name == 'create' then
    label = 'CREATE'
    detail = rel(action.dst)
  elseif action.name == 'delete' then
    label = has_trash() and ' TRASH' or 'DELETE'
    detail = rel(action.src)
  elseif action.name == 'move' then
    label = '  MOVE'
    detail = rel(action.src) .. ' -> ' .. rel(action.dst)
  elseif action.name == 'copy' then
    label = '  COPY'
    detail = rel(action.src) .. ' -> ' .. rel(action.dst)
  else
    label = action.name:upper()
    detail = '?'
  end
  return label .. ' ' .. detail, label
end

function M.sort_actions(actions)
  return M.plan_actions(actions)
end

return M
