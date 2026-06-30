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
  for _, l in ipairs(all_lines) do
    if #l > 0 then
      out[#out + 1] = l
      local lid, _, _, lis_dir = M.parse_line(l)
      if lis_dir and lid and session.store[lid] then
        local labs = session.store[lid].abs_path
        if not session.expanded_dirs[labs] and session.saved_children[labs] then
          for _, cl in ipairs(session.saved_children[labs]) do
            out[#out + 1] = cl
          end
        end
      end
    end
  end
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

function M.execute_actions(actions)
  -- build sets of paths that each action occupies/frees
  local dst_paths = {} -- paths that will be written to (need to be free)
  local src_paths = {} -- paths that will be freed (delete src, move src)
  for _, a in ipairs(actions) do
    if a.dst then
      dst_paths[strip_trailing_slash(a.dst)] = true
    end
    if a.name == 'delete' then
      src_paths[a.src] = true
    elseif a.name == 'move' and a.src then
      src_paths[a.src] = true
    end
  end

  -- detect path-swap cycles: move A->B and move B->A (mutual src/dst dependency).
  -- For each such pair we route one move via a temp path so neither clobbers the other.
  local move_by_src = {}
  for i, a in ipairs(actions) do
    if a.name == 'move' and a.src then
      move_by_src[strip_trailing_slash(a.src)] = i
    end
  end
  local detour = {} -- i -> { stage1 = { name='move', src=src, dst=tmp }, stage2 = { name='move', src=tmp, dst=dst } }
  local seen_cycle = {}
  for i, a in ipairs(actions) do
    if a.name == 'move' and a.src and not seen_cycle[i] then
      local src = strip_trailing_slash(a.src)
      local dst = strip_trailing_slash(a.dst)
      local j = move_by_src[dst]
      if j and j ~= i then
        local other = actions[j]
        if strip_trailing_slash(other.dst) == src then
          local tmp = src .. '.fs-edit-swap-' .. i
          detour[i] = {
            stage1 = { name = 'move', src = a.src, dst = tmp },
            stage2 = { name = 'move', src = tmp, dst = a.dst },
          }
          seen_cycle[i] = true
          seen_cycle[j] = true
        end
      end
    end
  end

  -- phase 1: actions that free paths needed by others (delete/move whose src = another action's dst)
  local ordered = {}
  local done = {}
  for i, a in ipairs(actions) do
    if a.name == 'delete' and dst_paths[a.src] then
      table.insert(ordered, a); done[i] = true
    end
  end
  -- moves whose src is needed by a create (rename A→B then create new A)
  for i, a in ipairs(actions) do
    if not done[i] and a.name == 'move' and a.src and dst_paths[a.src] then
      if detour[i] then
        table.insert(ordered, detour[i].stage1)
      else
        table.insert(ordered, a)
      end
      done[i] = true
    end
  end
  -- phase 2: creates
  for i, a in ipairs(actions) do
    if not done[i] and a.name == 'create' then
      table.insert(ordered, a); done[i] = true
    end
  end
  -- phase 3: remaining moves
  for i, a in ipairs(actions) do
    if not done[i] and a.name == 'move' then
      if detour[i] then
        table.insert(ordered, detour[i].stage1)
      else
        table.insert(ordered, a)
      end
      done[i] = true
    end
  end
  -- phase 4: copies
  for i, a in ipairs(actions) do
    if not done[i] and a.name == 'copy' then
      table.insert(ordered, a); done[i] = true
    end
  end
  -- phase 5: remaining deletes
  for i, a in ipairs(actions) do
    if not done[i] and a.name == 'delete' then
      table.insert(ordered, a); done[i] = true
    end
  end
  -- phase 6: finalize swap detours (tmp -> final dst)
  for i, _ in pairs(detour) do
    table.insert(ordered, detour[i].stage2)
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
      local src = strip_trailing_slash(action.src)
      local dst = strip_trailing_slash(action.dst)
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
      local src = strip_trailing_slash(action.src)
      local dst = strip_trailing_slash(action.dst)
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
  local type_order = { create = 1, move = 2, copy = 3, delete = 4 }
  local sorted = {}
  for _, a in ipairs(actions) do sorted[#sorted + 1] = a end
  table.sort(sorted, function(a, b) return (type_order[a.name] or 9) < (type_order[b.name] or 9) end)
  return sorted
end

return M
