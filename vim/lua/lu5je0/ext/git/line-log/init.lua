local Block = require('lu5je0.ext.git.line-log.block')
local ui = require('lu5je0.ext.git.line-log.ui')

local M = {}

local state = {
  job = nil,
  diff_job = nil,
  log_buf = nil,
  diff_buf = nil,
  log_win = nil,
  diff_win = nil,
  file = nil,
  rel_file = nil,
  repo_root = nil,
  start_line = nil,
  end_line = nil,
  commit_count = 0,
  spinner_idx = 1,
  spinner_timer = nil,
  -- block tracking data
  revisions = {}, -- list of {hash, date, message}
  blocks = {}, -- list of {start, end, lines}
  current_idx = 0,
  cancelled = false,
}

local function kill_job()
  state.cancelled = true
  ui.stop_spinner(state)
  if state.job then
    pcall(function()
      state.job:kill()
    end)
    state.job = nil
  end
  if state.diff_job then
    pcall(function()
      state.diff_job:kill()
    end)
    state.diff_job = nil
  end
end

local function cleanup_state()
  kill_job()
  state.log_buf = nil
  state.log_win = nil
  state.diff_buf = nil
  state.diff_win = nil
  state.revisions = {}
  state.blocks = {}
  state.current_idx = 0
end

-- Load file content at a specific revision
local function load_file_content(rev_hash, rel_file, callback)
  local cmd = { 'git', 'show', rev_hash .. ':' .. rel_file }
  state.job = vim.system(cmd, { text = true, cwd = state.repo_root }, function(result)
    vim.schedule(function()
      state.job = nil
      if state.cancelled then
        return
      end
      if result.code ~= 0 then
        callback(nil)
        return
      end
      local lines = vim.split(result.stdout or '', '\n', { plain = true })
      -- Remove trailing empty line if present
      if #lines > 0 and lines[#lines] == '' then
        lines[#lines] = nil
      end
      callback(lines)
    end)
  end)
end

-- Process next revision
local function process_next_revision()
  if state.cancelled then
    return
  end
  if not vim.api.nvim_buf_is_valid(state.log_buf) then
    kill_job()
    return
  end

  state.current_idx = state.current_idx + 1
  local idx = state.current_idx

  if idx > #state.revisions then
    -- Done
    ui.stop_spinner(state)
    ui.update_log_statusline(state, false)
    if state.commit_count == 0 then
      ui.set_buffer_lines(state.log_buf, { '-- No commits found --' })
    end
    return
  end

  local rev = state.revisions[idx]
  local prev_block = state.blocks[idx - 1]

  load_file_content(rev.hash, rev.file, function(lines)
    if state.cancelled then
      return
    end
    if not lines then
      -- File doesn't exist in this revision, stop here
      ui.stop_spinner(state)
      ui.update_log_statusline(state, false)
      return
    end

    local new_block = prev_block:create_previous_block(lines)

    state.blocks[idx] = new_block

    -- Check if block content changed from previous version
    -- Compare even when new_block is empty: non-empty -> empty is a content change
    -- (matches IDEA's filteredRevisions: checks getLines().equals() before EMPTY_BLOCK break)
    if not prev_block:content_equals(new_block) then
      -- Content changed, the previous revision (newer) introduced this change
      -- For idx=1, prev is current buffer (skip showing local changes)
      -- For idx>1, prev is revisions[idx-1]
      if idx > 1 then
        ui.append_commit_line(state, state.revisions[idx - 1])
      end
    end

    -- If block became empty, stop processing (matches IDEA's EMPTY_BLOCK break)
    if new_block:is_empty() then
      ui.stop_spinner(state)
      ui.update_log_statusline(state, false)
      return
    end

    -- If this is the last revision and block exists, show it (initial creation)
    if idx == #state.revisions then
      ui.append_commit_line(state, rev)
    end

    -- Continue to next revision
    process_next_revision()
  end)
end

-- Get list of revisions for the file
local function load_revisions()
  local cmd = {
    'git',
    'log',
    '--format=%h %ad %s%x00%an',
    '--date=format:%Y-%m-%d %H:%M:%S',
    '--abbrev=8',
    '--follow',
    '--name-only',
    '--',
    state.rel_file,
  }

  state.job = vim.system(cmd, { text = true, cwd = state.repo_root }, function(result)
    vim.schedule(function()
      state.job = nil
      if state.cancelled then
        return
      end
      if result.code ~= 0 or not result.stdout or result.stdout == '' then
        ui.stop_spinner(state)
        ui.update_log_statusline(state, false)
        ui.set_buffer_lines(state.log_buf, { '-- No commits found --' })
        return
      end

      state.revisions = {}
      local current_hash, current_date, current_message, current_author
      for line in result.stdout:gmatch('[^\n]*') do
        local hash, rest = line:match('^(%x+)%s+(.*)$')
        if hash and rest then
          local date, message = rest:match('^([%d%-]+%s+[%d:]+)%s+(.*)$')
          if date then
            local msg, author = message:match('^(.-)%z(.*)$')
            current_hash = hash
            current_date = date
            current_message = msg or message or ''
            current_author = author or ''
          end
        elseif current_hash and line ~= '' then
          table.insert(state.revisions, {
            hash = current_hash,
            date = current_date,
            message = current_message,
            author = current_author,
            file = line,
          })
          current_hash = nil
        end
      end

      if #state.revisions == 0 then
        ui.stop_spinner(state)
        ui.update_log_statusline(state, false)
        ui.set_buffer_lines(state.log_buf, { '-- No commits found --' })
        return
      end

      -- Load current file content as base
      local current_lines = vim.api.nvim_buf_get_lines(vim.fn.bufnr(state.file), 0, -1, false)
      state.blocks[0] = Block.new(current_lines, state.start_line, state.end_line)

      -- Start processing revisions
      process_next_revision()
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
  if state.log_win and vim.api.nvim_win_is_valid(state.log_win) then
    vim.api.nvim_win_close(state.log_win, true)
  end
  if state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) then
    vim.api.nvim_win_close(state.diff_win, true)
  end

  state.file = file
  state.rel_file = file:sub(#repo_root + 2)
  state.repo_root = repo_root
  state.start_line = start_line
  state.end_line = end_line
  state.commit_count = 0
  state.revisions = {}
  state.blocks = {}
  state.current_idx = 0
  state.cancelled = false

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

  ui.start_spinner(state)
  ui.setup_log_buffer_keymaps(state, kill_job)

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
