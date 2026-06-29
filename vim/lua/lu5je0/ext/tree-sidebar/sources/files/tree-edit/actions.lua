local M = {}

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
  local is_dir = vim.endswith(name, '/')
  return id, name, depth, is_dir
end

function M.compute_actions(session, buf_lines)
  local parse_line = M.parse_line
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
  local parse_line = M.parse_line
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

function M.execute_actions(actions)
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
