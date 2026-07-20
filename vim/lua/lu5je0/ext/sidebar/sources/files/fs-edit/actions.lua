-- Action layer: ordering (plan_actions) and filesystem execution
-- (execute_actions) for the create/delete/move/copy lists produced by
-- model.diff(). Knows nothing about buffers or the working tree.
local fmt = require('lu5je0.ext.sidebar.sources.files.fs-edit.format')

local M = {}

-- re-exports for tests and callers that only need the text format
M.PLACEHOLDER = fmt.PLACEHOLDER
M.parse_line = fmt.parse_line

local function has_trash()
  return vim.fn.executable('q-trash') == 1
end
M.has_trash = has_trash

local function trash(abs_paths)
  local cmd = { 'q-trash', 'rm', '-rf' }
  vim.list_extend(cmd, abs_paths)
  local result = vim.system(cmd):wait()
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
    local res = vim.fn.system({ 'cp', '-a', src, dst })
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
        -- Follow the dst->src chain; if it loops back to `a` we have a move
        -- cycle (A<->B swap is the length-2 case). Break it by staging a.src
        -- through a temp name: stage1 frees a.src, the rest of the cycle can
        -- then proceed, and stage2 fills the last vacated dst.
        local chain = { a }
        local in_chain = { [a] = true }
        local cur = a
        while true do
          local nxt = move_by_src[strip(cur.dst)]
          if not nxt or in_chain[nxt] then break end
          chain[#chain + 1] = nxt
          in_chain[nxt] = true
          cur = nxt
        end
        if move_by_src[strip(cur.dst)] == a and #chain > 1 then
          local tmp = strip(a.src) .. '.fs-edit-swap-' .. i
          local stage1 = { name = 'move', src = a.src, dst = tmp }
          stage1._provides_tmp = tmp
          local stage2 = { name = 'move', src = tmp, dst = a.dst }
          stage2._after_action = chain[#chain]
          expanded[#expanded + 1] = stage1
          for k = 2, #chain do
            expanded[#expanded + 1] = chain[k]
            handled[chain[k]] = true
          end
          expanded[#expanded + 1] = stage2
          handled[a] = true
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
        -- Consumer runs before the writer that clobbers the consumed path:
        -- move/delete free a path (or subtree) before a create/move/copy
        -- writes into it. Covers delete->create and move->create at equal
        -- paths (rename + recreate would otherwise truncate the source).
        -- Exceptions: (1) cycle staging writes a temp name that its own
        -- stage2 consumes; that pair must run writer-first. (2) a writer
        -- whose read source is inside the consumed subtree operates in the
        -- pre-consumption world (child move under a renamed parent); rule 1
        -- already orders it before the consumer.
        if a.consumes and b.writes and covers(a.consumes, b.writes)
          and not (b.reads and covers(a.consumes, b.reads))
          and b.action._provides_tmp ~= a.consumes then
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
    return nil, 'dependency cycle detected'
  end

  return ordered
end

function M.execute_actions(actions)
  local ordered, plan_err = M.plan_actions(actions)
  if not ordered then
    vim.notify('fs-edit: save aborted: ' .. plan_err .. '. Split the operation into smaller saves.', vim.log.levels.ERROR)
    return false
  end
  local function strip(p) return strip_trailing_slash(p) end

  local i = 1
  local n = #ordered
  while i <= n do
    local action = ordered[i]
    if action.name == 'create' then
      if vim.endswith(action.dst, '/') then
        if vim.fn.mkdir(action.dst:sub(1, -2), 'p') == 0 then
          vim.notify('fs-edit: mkdir failed: ' .. action.dst, vim.log.levels.ERROR)
        end
      else
        local parent = vim.fs.dirname(action.dst)
        vim.fn.mkdir(parent, 'p')
        local fd = vim.uv.fs_open(action.dst, 'w', 420)
        if fd then
          vim.uv.fs_close(fd)
        else
          vim.notify('fs-edit: create failed: ' .. action.dst, vim.log.levels.ERROR)
        end
      end
      i = i + 1
    elseif action.name == 'delete' then
      -- Coalesce a run of consecutive deletes into one q-trash spawn.
      -- Pure deletes have no ordering constraint among themselves, so
      -- batching is safe; we never merge across create/move/copy.
      local batch = {}
      while i <= n and ordered[i].name == 'delete' do
        table.insert(batch, ordered[i].src)
        i = i + 1
      end
      if has_trash() then
        if not trash(batch) then
          vim.notify('fs-edit: trash failed: ' .. table.concat(batch, ', '), vim.log.levels.ERROR)
        end
      else
        for _, src in ipairs(batch) do
          if vim.fn.delete(src, 'rf') ~= 0 then
            vim.notify('fs-edit: delete failed: ' .. src, vim.log.levels.ERROR)
          end
        end
      end
      for _, src in ipairs(batch) do
        close_bufs_under(src)
      end
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
      i = i + 1
    elseif action.name == 'copy' then
      local src = strip(action.src)
      local dst = strip(action.dst)
      local new_parent = vim.fs.dirname(dst)
      if not vim.uv.fs_stat(new_parent) then
        vim.fn.mkdir(new_parent, 'p')
      end
      local res = vim.fn.system({ 'cp', '-a', src, dst })
      if vim.v.shell_error ~= 0 then
        vim.notify('fs-edit: copy failed: ' .. tostring(res), vim.log.levels.ERROR)
      end
      i = i + 1
    else
      i = i + 1
    end
  end
  return true
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
