local Block = require('lu5je0.ext.git.line-log.block')
local blob_store = require('lu5je0.ext.git.line-log.blob-store')

local M = {}
local PREFETCH_BATCH_SIZE = 100

function M.parse_revisions_with_status(stdout, default_path)
  local result = {}
  local current = nil
  for line in stdout:gmatch('[^\n]*') do
    if line:find('%z') then
      if current then
        current.file = default_path
        current.status = 'M'
        result[#result + 1] = current
      end
      local hash_part, date, message, author = line:match('^(.-)%z(.-)%z(.-)%z(.*)$')
      if hash_part then
        local full, short = hash_part:match('^(%x+) (%x+)')
        if full then
          current = { full = full, hash = short, date = date, message = message, author = author }
        end
      end
    elseif current and line ~= '' then
      local parts = vim.split(line, '\t', { plain = true })
      current.status = parts[1] and parts[1]:sub(1, 1) or 'M'
      if current.status == 'R' or current.status == 'C' then
        current.file = parts[3] or default_path
      else
        current.file = parts[2] or default_path
      end
      result[#result + 1] = current
      current = nil
    end
  end
  if current then
    current.file = default_path
    current.status = 'M'
    result[#result + 1] = current
  end
  return result
end

function M.extract_rename_source_path(stdout)
  if not stdout then
    return nil
  end
  for line in stdout:gmatch('[^\n]+') do
    if line:match('^R') and line:find('\t') then
      local parts = vim.split(line, '\t', { plain = true })
      if #parts >= 3 then
        return parts[2]
      end
      break
    end
  end
  return nil
end

local function run_git_sync(repo_root, cmd)
  local result = vim.system(cmd, { text = true, cwd = repo_root }):wait()
  if result.code ~= 0 then
    return nil, result.stderr or ('git exited with code ' .. result.code)
  end
  return result.stdout
end

local function set_async_job(opts, job)
  if opts and opts.on_job then
    opts.on_job(job)
  end
end

local function is_async_active(opts)
  if opts and opts.is_active then
    return opts.is_active()
  end
  return true
end

local function make_log_command(commit, path)
  return {
    'git', 'log', commit,
    '--format=%H %h%x00%ad%x00%s%x00%an',
    '--date=format:%Y-%m-%d %H:%M:%S',
    '--abbrev=8',
    '--name-status',
    '--full-history', '--simplify-merges',
    '--', path,
  }
end

local function make_rename_probe_command(commit, path)
  return {
    'git', 'show', '-M', '--follow', '--name-status',
    '--format=%H %h', commit, '--', path,
  }
end

local function append_revision_once(revisions, visited, entry)
  if visited[entry.full] then
    return false
  end
  visited[entry.full] = true
  revisions[#revisions + 1] = {
    hash = entry.hash,
    full = entry.full,
    date = entry.date,
    message = entry.message,
    author = entry.author,
    file = entry.file,
  }
  return true
end

function M.resolve_head_async(repo_root, opts, callback)
  local job
  job = vim.system({ 'git', 'rev-parse', 'HEAD' }, { text = true, cwd = repo_root }, function(result)
    vim.schedule(function()
      if not is_async_active(opts) then
        return
      end
      set_async_job(opts, nil)
      local head = result.code == 0 and (result.stdout or ''):match('%x+') or nil
      callback(head, result)
    end)
  end)
  set_async_job(opts, job)
  return job
end

function M.collect_revisions_sync(repo_root, head_commit, rel_file)
  local visited = {}
  local revisions = {}
  local queue = { { commit = head_commit, path = rel_file } }

  while #queue > 0 do
    local item = table.remove(queue, 1)
    local log_out = run_git_sync(repo_root, make_log_command(item.commit, item.path))

    if log_out then
      local last_add_commit = nil
      local entries = M.parse_revisions_with_status(log_out, item.path)
      for _, entry in ipairs(entries) do
        if append_revision_once(revisions, visited, entry) then
          if entry.status == 'A' then
            last_add_commit = entry.full
            break
          end
        end
      end

      if last_add_commit then
        local show_out = run_git_sync(repo_root, make_rename_probe_command(last_add_commit, item.path))
        local rename_source = M.extract_rename_source_path(show_out)
        if rename_source then
          queue[#queue + 1] = { commit = last_add_commit, path = rename_source }
        end
      end
    end
  end

  return revisions
end

function M.collect_revisions_async(repo_root, head_commit, rel_file, opts, callback)
  local visited = {}
  local revisions = {}
  local queue = { { commit = head_commit, path = rel_file } }

  local function process_queue()
    if not is_async_active(opts) then
      return
    end
    if #queue == 0 then
      callback(revisions)
      return
    end

    local item = table.remove(queue, 1)
    local job
    job = vim.system(make_log_command(item.commit, item.path), { text = true, cwd = repo_root }, function(result)
      vim.schedule(function()
        if not is_async_active(opts) then
          return
        end
        set_async_job(opts, nil)
        if result.code ~= 0 or not result.stdout then
          process_queue()
          return
        end

        local entries = M.parse_revisions_with_status(result.stdout, item.path)
        local last_add_commit = nil
        for _, entry in ipairs(entries) do
          if append_revision_once(revisions, visited, entry) then
            if entry.status == 'A' then
              last_add_commit = entry.full
              break
            end
          end
        end

        if not last_add_commit then
          process_queue()
          return
        end

        local rename_job
        rename_job = vim.system(make_rename_probe_command(last_add_commit, item.path), { text = true, cwd = repo_root }, function(show_result)
          vim.schedule(function()
            if not is_async_active(opts) then
              return
            end
            set_async_job(opts, nil)
            if show_result.code == 0 and show_result.stdout then
              local rename_source = M.extract_rename_source_path(show_result.stdout)
              if rename_source then
                queue[#queue + 1] = { commit = last_add_commit, path = rename_source }
              end
            end
            process_queue()
          end)
        end)
        set_async_job(opts, rename_job)
      end)
    end)
    set_async_job(opts, job)
  end

  process_queue()
end

function M.build_prefetch_specs(revisions)
  local specs = {}
  for _, rev in ipairs(revisions or {}) do
    specs[#specs + 1] = { rev = rev.full, file = rev.file }
  end
  return specs
end

function M.initialize_tracker(current_lines, start_line, end_line, revisions)
  local lines = vim.deepcopy(current_lines or {})
  lines[#lines + 1] = ''
  return {
    revisions = revisions or {},
    blocks = {
      [0] = Block.new(lines, start_line, end_line),
    },
    current_idx = 0,
    local_change_block = nil,
    last_evicted_idx = 0,
  }
end

function M.step_tracker(tracker, get_lines, opts)
  local batch_size = (opts and opts.prefetch_batch_size) or PREFETCH_BATCH_SIZE
  local idx = tracker.current_idx + 1

  if idx > #tracker.revisions then
    return { exhausted = true, current_idx = tracker.current_idx }
  end

  local rev = tracker.revisions[idx]
  local lines = get_lines(rev.full, rev.file)
  if not lines then
    return {
      waiting_for_prefetch = true,
      revision = rev,
      current_idx = tracker.current_idx,
    }
  end

  tracker.current_idx = idx
  local prev_block = tracker.blocks[idx - 1]:create_previous_block(lines)
  tracker.blocks[idx] = prev_block

  local changed = not tracker.blocks[idx - 1]:content_equals(prev_block)
  local appended_revisions = {}

  if changed and idx == 1 then
    tracker.local_change_block = prev_block
  end

  if changed and idx > 1 then
    appended_revisions[#appended_revisions + 1] = {
      revision = tracker.revisions[idx - 1],
      revision_idx = idx - 1,
    }
  end

  local evict_to = nil
  local done = false
  if prev_block:is_empty() then
    done = true
    evict_to = idx
  elseif idx == #tracker.revisions then
    appended_revisions[#appended_revisions + 1] = {
      revision = rev,
      revision_idx = idx,
    }
    evict_to = idx
  elseif idx - tracker.last_evicted_idx >= batch_size then
    evict_to = idx
  end

  if evict_to then
    tracker.last_evicted_idx = evict_to
  end

  return {
    done = done,
    current_idx = idx,
    changed = changed,
    local_change = changed and idx == 1,
    appended_revisions = appended_revisions,
    evict_to = evict_to,
    block = prev_block,
  }
end

function M.track_commits_sync(opts)
  local repo_root = opts.repo_root
  local commit = opts.commit
  local rel_file = opts.file
  local start_line = opts.start_line
  local end_line = opts.end_line
  local store = opts.store or blob_store.for_repo(repo_root)

  store:clear()
  local revisions = M.collect_revisions_sync(repo_root, commit, rel_file)
  local specs = {
    { rev = commit, file = rel_file },
  }
  vim.list_extend(specs, M.build_prefetch_specs(revisions))
  local ok, err = store:prefetch_sync(specs)
  if not ok then
    error(err)
  end

  local current_lines = store:get_lines(commit, rel_file)
  if not current_lines then
    return {
      revisions = revisions,
      shown_commits = {},
    }
  end

  local tracker = M.initialize_tracker(current_lines, start_line, end_line, revisions)
  local shown = {}

  while true do
    local step = M.step_tracker(tracker, function(rev, file)
      return store:get_lines(rev, file)
    end)
    if step.waiting_for_prefetch or step.exhausted then
      break
    end

    for _, entry in ipairs(step.appended_revisions) do
      shown[#shown + 1] = entry.revision.hash
    end
    if step.done then
      break
    end
  end

  return {
    revisions = revisions,
    shown_commits = shown,
  }
end

return M
