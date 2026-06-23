local M = {}

local log_path = vim.fn.stdpath('log') .. '/git-status.log'
local batch_counter = 0

-- ── logging ─────────────────────────────────────────────

local function log_write(line)
  vim.fn.writefile({ line }, log_path, 'a')
end

local function log_timestamp()
  return os.date('%Y-%m-%d %H:%M:%S')
end

local function log_new_batch_id()
  batch_counter = batch_counter + 1
  return string.format('%08x', (os.time() * 256 + batch_counter) % 0xffffffff)
end

function M.log_batch(action, kind, count, body_fn)
  local id = log_new_batch_id()
  local files_word = count == 1 and 'file' or 'files'
  log_write(string.format('%s [%s] BEGIN %s %s (%d %s)', log_timestamp(), id, action, kind, count, files_word))
  local ok_count = body_fn(function(msg)
    log_write(string.format('%s [%s]   %s', log_timestamp(), id, msg))
  end)
  local status
  if (ok_count or count) == count then
    status = 'ok'
  elseif (ok_count or count) == 0 then
    status = 'fail'
  else
    status = 'partial'
  end
  log_write(string.format('%s [%s] END %s %s %d/%d', log_timestamp(), id, action, status, ok_count or count, count))
end

-- ── git command helpers ─────────────────────────────────

function M.run_git(args, error_prefix, cwd)
  cwd = cwd or vim.fn.getcwd()
  local result = vim.system(args, { text = true, cwd = cwd }):wait()
  if result.code ~= 0 then
    local stderr = (result.stderr or ''):gsub('%s+$', '')
    vim.notify(string.format('%s%s', error_prefix or 'Git command failed: ', stderr), vim.log.levels.ERROR)
    return false, result
  end
  return true, result
end

function M.hash_file(abs_path, write, cwd)
  local args = { 'git', 'hash-object' }
  if write then args[#args + 1] = '-w' end
  args[#args + 1] = abs_path
  local ok, result = M.run_git(args, 'Failed to hash file: ', cwd)
  if not ok then return nil end
  local blob = (result.stdout or ''):gsub('%s+$', '')
  return blob ~= '' and blob or nil
end

-- ── undo system ─────────────────────────────────────────

function M.push_undo(stack, label, ops)
  if ops and #ops > 0 then
    stack[#stack + 1] = { label = label, ops = ops }
  end
end

local function undo_restore_blobs(op, cwd)
  local verify_paths = {}
  local verify_indices = {}
  for i, file in ipairs(op.files or {}) do
    local abs_path = cwd .. '/' .. file.path
    if file.expected_absent then
      if vim.uv.fs_stat(abs_path) then
        vim.notify('Undo skipped: ' .. abs_path .. ' already exists', vim.log.levels.WARN)
        return false
      end
    elseif file.expected_blob then
      if not vim.uv.fs_stat(abs_path) then
        vim.notify('Undo skipped: ' .. abs_path .. ' no longer exists', vim.log.levels.WARN)
        return false
      end
      verify_paths[#verify_paths + 1] = abs_path
      verify_indices[#verify_indices + 1] = i
    else
      vim.notify('Undo skipped: cannot verify ' .. abs_path, vim.log.levels.WARN)
      return false
    end
  end
  if #verify_paths > 0 then
    local result = vim.system({ 'git', 'hash-object', '--stdin-paths' }, { text = true, cwd = cwd, stdin = table.concat(verify_paths, '\n') }):wait()
    if result.code ~= 0 then
      vim.notify('Undo failed: cannot hash files', vim.log.levels.ERROR)
      return false
    end
    local idx = 1
    for line in (result.stdout or ''):gmatch('[^\n]+') do
      local file = op.files[verify_indices[idx]]
      if line ~= file.expected_blob then
        vim.notify('Undo skipped: ' .. cwd .. '/' .. file.path .. ' changed after discard', vim.log.levels.WARN)
        return false
      end
      idx = idx + 1
    end
  end

  local restore_files = {}
  for _, file in ipairs(op.files or {}) do
    local abs_path = cwd .. '/' .. file.path
    if file.delete then
      os.remove(abs_path)
    else
      restore_files[#restore_files + 1] = { blob = file.blob, abs_path = abs_path }
    end
  end
  if #restore_files > 0 then
    local stdin = ''
    for _, rf in ipairs(restore_files) do
      stdin = stdin .. rf.blob .. '\n'
    end
    local result = vim.system({ 'git', 'cat-file', '--batch' }, { cwd = cwd, stdin = stdin }):wait()
    if result.code ~= 0 then
      vim.notify('Undo failed: cannot read blobs', vim.log.levels.ERROR)
      return false
    end
    local stdout = result.stdout or ''
    local pos = 1
    for _, rf in ipairs(restore_files) do
      local header_end = stdout:find('\n', pos)
      if not header_end then
        vim.notify('Failed to restore ' .. rf.abs_path, vim.log.levels.ERROR)
        return false
      end
      local header = stdout:sub(pos, header_end - 1)
      local size = tonumber(header:match('%d+$'))
      if not size then
        vim.notify('Failed to restore ' .. rf.abs_path, vim.log.levels.ERROR)
        return false
      end
      local content = stdout:sub(header_end + 1, header_end + size)
      pos = header_end + size + 2
      vim.fn.mkdir(vim.fn.fnamemodify(rf.abs_path, ':h'), 'p')
      local fd = vim.uv.fs_open(rf.abs_path, 'w', 420)
      if not fd then
        vim.notify('Failed to open ' .. rf.abs_path, vim.log.levels.ERROR)
        return false
      end
      vim.uv.fs_write(fd, content, 0)
      vim.uv.fs_close(fd)
    end
  end
  return true
end

function M.index_snapshot(cwd, paths)
  local args = { 'git', 'ls-files', '-s', '--' }
  for _, p in ipairs(paths) do args[#args + 1] = p end
  local result = vim.system(args, { text = true, cwd = cwd }):wait()
  if result.code ~= 0 then return nil end
  return result.stdout or ''
end

function M.run_undo_op(op, cwd)
  if op.type == 'reset_paths' or op.type == 'add_paths' then
    if op.expected_index then
      local current = M.index_snapshot(cwd, op.paths)
      if current ~= op.expected_index then
        vim.notify('Undo skipped: index has changed since operation', vim.log.levels.WARN)
        return false
      end
    end
    local cmd = op.type == 'reset_paths' and 'reset' or 'add'
    local args
    if cmd == 'reset' then
      args = { 'git', 'reset', 'HEAD', '--' }
    else
      args = { 'git', 'add', '--' }
    end
    for _, p in ipairs(op.paths or {}) do args[#args + 1] = p end
    return M.run_git(args, 'Undo failed: ', cwd)
  elseif op.type == 'restore_blobs' then
    return undo_restore_blobs(op, cwd)
  elseif op.type == 'store_stash' then
    return M.run_git({ 'git', 'stash', 'store', '-m', op.message, op.sha }, 'Undo failed: ', cwd)
  elseif op.type == 'drop_stash_by_sha' then
    local list_result = vim.system({ 'git', 'stash', 'list', '--format=%gd %H' }, { text = true, cwd = cwd }):wait()
    if list_result.code ~= 0 then
      vim.notify('Failed to list stashes', vim.log.levels.ERROR)
      return false
    end
    local target_ref
    for line in (list_result.stdout or ''):gmatch('[^\n]+') do
      local ref, sha = line:match('^(%S+)%s+(%S+)')
      if sha == op.sha then target_ref = ref; break end
    end
    if not target_ref then
      vim.notify('Stash not found', vim.log.levels.WARN)
      return false
    end
    return M.run_git({ 'git', 'stash', 'drop', target_ref }, 'Failed to drop stash: ', cwd)
  end
  return false
end

function M.compute_inverse_entry(entry, cwd)
  local inv_ops = {}
  for _, op in ipairs(entry.ops) do
    if op.type == 'reset_paths' then
      local snapshot = M.index_snapshot(cwd, op.paths)
      inv_ops[#inv_ops + 1] = { type = 'add_paths', paths = op.paths, expected_index = snapshot }
    elseif op.type == 'add_paths' then
      local snapshot = M.index_snapshot(cwd, op.paths)
      inv_ops[#inv_ops + 1] = { type = 'reset_paths', paths = op.paths, expected_index = snapshot }
    elseif op.type == 'restore_blobs' then
      local inv_files = {}
      for _, file in ipairs(op.files or {}) do
        local abs_path = cwd .. '/' .. file.path
        if file.delete then
          if file.expected_blob then
            inv_files[#inv_files + 1] = { path = file.path, blob = file.expected_blob, expected_absent = true }
          end
        elseif file.expected_absent then
          local blob = M.hash_file(abs_path, true, cwd)
          if blob then
            inv_files[#inv_files + 1] = { path = file.path, delete = true, expected_blob = blob }
          end
        else
          local current_blob = M.hash_file(abs_path, true, cwd)
          if current_blob and file.expected_blob then
            inv_files[#inv_files + 1] = { path = file.path, blob = file.expected_blob, expected_blob = current_blob }
          end
        end
      end
      inv_ops[#inv_ops + 1] = { type = 'restore_blobs', files = inv_files }
    elseif op.type == 'store_stash' then
      inv_ops[#inv_ops + 1] = { type = 'drop_stash_by_sha', sha = op.sha, message = op.message }
    elseif op.type == 'drop_stash_by_sha' then
      inv_ops[#inv_ops + 1] = { type = 'store_stash', sha = op.sha, message = op.message }
    end
  end
  return { label = entry.label, ops = inv_ops }
end

function M.undo_last_action(stack, cwd, callback, redo_stack)
  local entry = stack[#stack]
  if not entry then
    vim.notify('Nothing to undo', vim.log.levels.INFO)
    return
  end
  for i = #entry.ops, 1, -1 do
    if not M.run_undo_op(entry.ops[i], cwd) then
      return
    end
  end
  table.remove(stack)
  if redo_stack then
    local inverse = M.compute_inverse_entry(entry, cwd)
    redo_stack[#redo_stack + 1] = inverse
  end
  vim.notify('Undid ' .. entry.label, vim.log.levels.INFO)
  if callback then callback() end
end

function M.redo_last_action(redo_stack, undo_stack, cwd, callback)
  local entry = redo_stack[#redo_stack]
  if not entry then
    vim.notify('Nothing to redo', vim.log.levels.INFO)
    return
  end
  for i = #entry.ops, 1, -1 do
    if not M.run_undo_op(entry.ops[i], cwd) then
      return
    end
  end
  table.remove(redo_stack)
  local inverse = M.compute_inverse_entry(entry, cwd)
  undo_stack[#undo_stack + 1] = inverse
  vim.notify('Redid ' .. entry.label, vim.log.levels.INFO)
  if callback then callback() end
end

return M
