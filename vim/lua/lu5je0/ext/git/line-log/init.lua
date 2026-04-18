local blob_store = require('lu5je0.ext.git.line-log.blob-store')
local core = require('lu5je0.ext.git.line-log.core')
local ui = require('lu5je0.ext.git.line-log.ui')
local env_keeper = require('lu5je0.misc.env-keeper')

local M = {}

local hl_ns = vim.api.nvim_create_namespace('git_line_log_selected')
local PREFETCH_BATCH_SIZE = 100
local process_next_revision
local schedule_next_revision

local state = {
  session = 0,
  job = nil,
  prefetch_job = nil,
  diff_job = nil,
  log_buf = nil,
  diff_buf = nil,
  diff_buf2 = nil,
  log_win = nil,
  diff_win = nil,
  diff_win2 = nil,
  file = nil,
  rel_file = nil,
  repo_root = nil,
  start_line = nil,
  end_line = nil,
  commit_count = 0,
  display_items = {},
  cancelled = false,
  tracker = nil,
  prefetch_specs = {},
  next_prefetch_idx = 1,
  waiting_for_prefetch = false,
  -- diff mode: 'single' or 'dual' (vimdiff style)
  diff_mode = env_keeper.get('line_log_diff_mode', 'single'),
  blob_store = nil,
}

local function kill_job()
  state.cancelled = true
  if state.job then
    pcall(function()
      state.job:kill()
    end)
    state.job = nil
  end
  if state.prefetch_job then
    pcall(function()
      state.prefetch_job:kill()
    end)
    state.prefetch_job = nil
  end
  if state.diff_job then
    pcall(function()
      state.diff_job:kill()
    end)
    state.diff_job = nil
  end
end

local function is_active_session(session)
  return state.session == session and not state.cancelled
end

local function clear_source_highlight()
  if state.source_buf and vim.api.nvim_buf_is_valid(state.source_buf) then
    vim.api.nvim_buf_clear_namespace(state.source_buf, hl_ns, 0, -1)
  end
end

local function apply_source_highlight()
  if not state.source_buf or not vim.api.nvim_buf_is_valid(state.source_buf) then
    return
  end
  if not state.start_line or not state.end_line then
    return
  end
  vim.api.nvim_buf_clear_namespace(state.source_buf, hl_ns, 0, -1)
  for i = state.start_line, state.end_line do
    vim.api.nvim_buf_set_extmark(state.source_buf, hl_ns, i - 1, 0, {
      end_row = i,
      hl_group = 'Visual',
      hl_eol = true,
    })
  end
end

local function cleanup_state()
  kill_job()
  state.session = state.session + 1
  ui.close_help()
  clear_source_highlight()
  if state.hl_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.hl_augroup)
    state.hl_augroup = nil
  end
  state.source_buf = nil
  state.log_buf = nil
  state.log_win = nil
  state.diff_buf = nil
  state.diff_win = nil
  state.diff_buf2 = nil
  state.diff_win2 = nil
  state.tracker = nil
  state.display_items = {}
  state.prefetch_specs = {}
  state.next_prefetch_idx = 1
  state.waiting_for_prefetch = false
  state.blob_store = nil
end

local function close_windows()
  for _, win in ipairs({ state.diff_win2, state.diff_win, state.log_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
end

local function reset_session(file, repo_root, start_line, end_line)
  state.session = state.session + 1
  state.file = file
  state.rel_file = file:sub(#repo_root + 2)
  state.repo_root = repo_root
  state.start_line = start_line
  state.end_line = end_line
  state.commit_count = 0
  state.display_items = {}
  state.cancelled = false
  state.tracker = nil
  state.prefetch_specs = {}
  state.next_prefetch_idx = 1
  state.waiting_for_prefetch = false
  state.source_buf = vim.api.nvim_get_current_buf()
  state.blob_store = blob_store.for_repo(repo_root)
  state.blob_store:clear()
end

local function slice_specs(specs, start_idx, size)
  local chunk = {}
  local stop_idx = math.min(start_idx + size - 1, #specs)
  for i = start_idx, stop_idx do
    chunk[#chunk + 1] = specs[i]
  end
  return chunk, stop_idx + 1
end

local function prefetch_next_chunk(on_done)
  local session = state.session
  if not is_active_session(session) then
    return
  end
  if state.prefetch_job or state.next_prefetch_idx > #state.prefetch_specs then
    return
  end

  local chunk, next_idx = slice_specs(state.prefetch_specs, state.next_prefetch_idx, PREFETCH_BATCH_SIZE)
  state.next_prefetch_idx = next_idx
  state.prefetch_job = state.blob_store:prefetch_async(chunk, function(ok)
    if not is_active_session(session) then
      return
    end
    state.prefetch_job = nil
    if not ok then
      ui.update_log_statusline(state, false)
      if state.log_buf and vim.api.nvim_buf_is_valid(state.log_buf) then
        ui.set_buffer_lines(state.log_buf, { '-- Failed to load file history --' })
      end
      return
    end
    if on_done then
      on_done()
      on_done = nil
    end
    if state.waiting_for_prefetch then
      state.waiting_for_prefetch = false
      schedule_next_revision()
    end
    prefetch_next_chunk()
  end)
end

local function evict_processed_specs(end_idx)
  if not state.blob_store then
    return
  end
  local tracker = state.tracker
  local last_evicted_idx = tracker and tracker.last_evicted_idx or 0
  if end_idx <= last_evicted_idx then
    return
  end

  local specs = {}
  for i = last_evicted_idx + 1, end_idx do
    local spec = state.prefetch_specs[i]
    if spec then
      specs[#specs + 1] = spec
    end
  end
  state.blob_store:evict_specs(specs)
end

schedule_next_revision = function()
  local session = state.session
  vim.schedule(function()
    if is_active_session(session) then
      process_next_revision()
    end
  end)
end

-- Process next revision in the tracking loop
process_next_revision = function()
  local session = state.session
  if not is_active_session(session) then
    return
  end
  if not vim.api.nvim_buf_is_valid(state.log_buf) then
    kill_job()
    return
  end

  ui.update_log_statusline(state, true)
  local tracker = state.tracker
  if not tracker then
    ui.update_log_statusline(state, false)
    if state.commit_count == 0 then
      ui.set_buffer_lines(state.log_buf, { '-- No commits found --' })
    end
    return
  end

  local step = core.step_tracker(tracker, function(rev, file)
    return state.blob_store and state.blob_store:get_lines(rev, file) or nil
  end, { prefetch_batch_size = PREFETCH_BATCH_SIZE })

  if step.exhausted then
    ui.update_log_statusline(state, false)
    if state.commit_count == 0 then
      ui.set_buffer_lines(state.log_buf, { '-- No commits found --' })
    end
    return
  end

  if step.waiting_for_prefetch then
    state.waiting_for_prefetch = true
    prefetch_next_chunk()
    return
  end

  if step.local_change then
    ui.append_local_change_line(state)
  end

  for _, entry in ipairs(step.appended_revisions or {}) do
    ui.append_commit_line(state, entry.revision, entry.revision_idx)
  end

  if step.evict_to then
    evict_processed_specs(step.evict_to)
  end

  if step.done then
    ui.update_log_statusline(state, false)
    return
  end
  schedule_next_revision()
end

-- Start revision collection and block tracking
local function load_revisions()
  local session = state.session
  core.resolve_head_async(state.repo_root, {
    is_active = function()
      return is_active_session(session)
    end,
    on_job = function(job)
      state.job = job
    end,
  }, function(head, result)
    if not is_active_session(session) then
      return
    end
    if result.code ~= 0 then
      ui.update_log_statusline(state, false)
      ui.set_buffer_lines(state.log_buf, { '-- Not in a git repository --' })
      return
    end

    if not head then
      ui.update_log_statusline(state, false)
      ui.set_buffer_lines(state.log_buf, { '-- No commits found --' })
      return
    end

    core.collect_revisions_async(state.repo_root, head, state.rel_file, {
      is_active = function()
        return is_active_session(session)
      end,
      on_job = function(job)
        state.job = job
      end,
    }, function(revisions)
      if not is_active_session(session) then
        return
      end
      if #revisions == 0 then
        ui.update_log_statusline(state, false)
        ui.set_buffer_lines(state.log_buf, { '-- No commits found --' })
        return
      end

      local current_lines = vim.api.nvim_buf_get_lines(vim.fn.bufnr(state.file), 0, -1, false)
      state.tracker = core.initialize_tracker(current_lines, state.start_line, state.end_line, revisions)
      state.prefetch_specs = core.build_prefetch_specs(revisions)
      state.next_prefetch_idx = 1
      prefetch_next_chunk(function()
        if not is_active_session(session) then
          return
        end
        schedule_next_revision()
      end)
    end)
  end)
end

function M.show()
  local start_line = vim.fn.getpos('v')[2]
  local end_line = vim.api.nvim_win_get_cursor(0)[1]
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local file = vim.fn.expand('%:p')
  if file == '' then
    vim.notify('No file', vim.log.levels.WARN)
    return
  end

  local repo_root = vim.fs.root(file, '.git')
  if not repo_root then
    vim.notify('Not in a git repository', vim.log.levels.WARN)
    return
  end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)

  kill_job()
  close_windows()
  reset_session(file, repo_root, start_line, end_line)

  apply_source_highlight()

  local function toggle_diff_mode()
    state.diff_mode = state.diff_mode == 'single' and 'dual' or 'single'
    env_keeper.set('line_log_diff_mode', state.diff_mode)
    vim.notify('Diff mode: ' .. state.diff_mode, vim.log.levels.INFO)
  end

  state.log_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.log_buf].buftype = 'nofile'
  vim.bo[state.log_buf].bufhidden = 'wipe'
  vim.bo[state.log_buf].swapfile = false
  vim.bo[state.log_buf].filetype = 'git'

  vim.api.nvim_buf_set_lines(state.log_buf, 0, -1, false, { '-- Loading... --' })
  vim.bo[state.log_buf].modifiable = false

  local height = math.floor(vim.api.nvim_win_get_height(0) / 2)
  vim.cmd('botright split')
  state.log_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.log_win, state.log_buf)
  vim.api.nvim_win_set_height(state.log_win, height)

  ui.update_log_statusline(state, true)
  ui.setup_log_buffer_keymaps(state, toggle_diff_mode)

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = state.log_buf,
    once = true,
    callback = function()
      cleanup_state()
    end,
  })



  load_revisions()
end

return M
