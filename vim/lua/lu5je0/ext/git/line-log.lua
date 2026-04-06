local M = {}

local ns_id = vim.api.nvim_create_namespace('git_line_log')
local spinner = { '󰪞', '󰪟', '󰪠', '󰪡', '󰪢', '󰪣', '󰪤', '󰪥' }

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
  revisions = {},  -- list of {hash, date, message}
  blocks = {},     -- list of {start, end, lines}
  current_idx = 0,
  cancelled = false,
}

-- Block: tracks content and range
local Block = {}
Block.__index = Block

function Block.new(lines, start_line, end_line)
  start_line = math.max(1, math.min(start_line, #lines + 1))
  end_line = math.max(start_line - 1, math.min(end_line, #lines))
  return setmetatable({
    lines = lines,
    start_line = start_line,
    end_line = end_line,
  }, Block)
end

function Block:get_content()
  local result = {}
  for i = self.start_line, self.end_line do
    result[#result + 1] = self.lines[i] or ''
  end
  return result
end

function Block:is_empty()
  return self.start_line > self.end_line
end

function Block:content_equals(other)
  local a = self:get_content()
  local b = other:get_content()
  -- Strict comparison like IDEA's block1.getLines().equals(block2.getLines())
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

-- Trace block position from current to previous version using diff
-- This implements the same algorithm as IntelliJ IDEA's Block.createPreviousBlock
-- IDEA uses 0-based exclusive ranges [start, end), we convert at boundaries
function Block:create_previous_block(prev_lines, debug)
  if self:is_empty() then
    return Block.new(prev_lines, 1, 0)
  end

  local curr_text = table.concat(self.lines, '\n')
  local prev_text = table.concat(prev_lines, '\n')

  -- vim.diff with result_type='indices' returns list of {prev_start, prev_count, curr_start, curr_count}
  -- Use ignore_whitespace to match IDEA's ComparisonPolicy.IGNORE_WHITESPACES
  -- Use histogram algorithm: IDEA's ByLine diff is closest to histogram/patience;
  -- default myers produces overly large hunks that collapse the block prematurely
  local ok, hunks = pcall(vim.diff, prev_text, curr_text, {
    result_type = 'indices',
    ignore_whitespace = true,
    algorithm = 'histogram',
  })
  if not ok or not hunks then
    return Block.new(prev_lines, self.start_line, self.end_line)
  end

  -- Convert from 1-based inclusive to 0-based exclusive (IDEA's format)
  -- 1-based inclusive [a, b] -> 0-based exclusive [a-1, b)
  local start = self.start_line - 1  -- 0-based
  local end_ = self.end_line         -- exclusive (same numeric value)

  -- greedy: non-empty range should expand to include change boundaries when damaged
  -- In IDEA: greedy = myStart != myEnd (0-based exclusive)
  local greedy = start ~= end_

  local shift = 0

  -- Process hunks in forward order (matching IntelliJ's approach)
  for _, h in ipairs(hunks) do
    local ps, pc, cs, cc = h[1], h[2], h[3], h[4]
    -- ps, pc: start (1-based) and count in prev
    -- cs, cc: start (1-based) and count in curr

    -- Convert to IDEA's 0-based exclusive Range format
    -- When count > 0: start = position - 1 (normal 1-based to 0-based)
    -- When count = 0: start = position (vim.diff points to context line before gap)
    local range_start1 = pc > 0 and (ps - 1) or ps
    local range_end1 = pc > 0 and (ps - 1 + pc) or ps
    local range_start2 = cc > 0 and (cs - 1) or cs
    local range_end2 = cc > 0 and (cs - 1 + cc) or cs

    -- changeStart/End are in current coordinate system, adjusted by accumulated shift
    local changeStart = range_start2 + shift  -- 0-based
    local changeEnd = range_end2 + shift      -- 0-based exclusive
    local changeShift = (range_end1 - range_start1) - (range_end2 - range_start2)  -- = pc - cc

    if debug then
      print(string.format("  hunk: ps=%d pc=%d cs=%d cc=%d -> changeStart=%d changeEnd=%d shift=%d changeShift=%d",
        ps, pc, cs, cc, changeStart, changeEnd, shift, changeShift))
      print(string.format("  before: start=%d end=%d", start, end_))
    end

    -- Apply updateRangeOnModification logic (matching IntelliJ's DiffUtil exactly)
    -- All comparisons use 0-based exclusive ranges
    if end_ <= changeStart then
      -- change is after our range (no effect)
      if debug then print("    -> change after range, no shift") end
    elseif start >= changeEnd then
      -- change is before our range (apply shift)
      start = start + changeShift
      end_ = end_ + changeShift
      if debug then print(string.format("    -> change before range, shift by %d", changeShift)) end
    elseif start <= changeStart and end_ >= changeEnd then
      -- change is inside our range
      end_ = end_ + changeShift
      if debug then print(string.format("    -> change inside range, end shift by %d", changeShift)) end
    else
      -- Range is damaged
      local newChangeEnd = changeEnd + changeShift

      if start >= changeStart and end_ <= changeEnd then
        -- fully inside change
        if greedy then
          start = range_start1
          end_ = range_end1
        else
          start = newChangeEnd
          end_ = newChangeEnd
        end
        if debug then print(string.format("    -> fully inside change, greedy=%s", tostring(greedy))) end
      elseif start < changeStart then
        -- bottom boundary damaged
        if greedy then
          end_ = newChangeEnd
        else
          end_ = changeStart
        end
        if debug then print(string.format("    -> bottom boundary damaged, greedy=%s", tostring(greedy))) end
      else
        -- top boundary damaged
        if greedy then
          start = range_start1
          end_ = end_ + changeShift
        else
          start = newChangeEnd
          end_ = end_ + changeShift
        end
        if debug then print(string.format("    -> top boundary damaged, greedy=%s", tostring(greedy))) end
      end
    end

    if debug then
      print(string.format("  after: start=%d end=%d", start, end_))
    end

    shift = shift + changeShift
  end

  -- Convert back from 0-based exclusive to 1-based inclusive
  -- 0-based exclusive [a, b) -> 1-based inclusive [a+1, b]
  local result_start = start + 1
  local result_end = end_

  -- Clamp to valid range
  result_start = math.max(1, result_start)
  result_end = math.max(result_start - 1, math.min(#prev_lines, result_end))

  return Block.new(prev_lines, result_start, result_end)
end

-- UI helpers
local function update_log_statusline(loading)
  if not state.log_win or not vim.api.nvim_win_is_valid(state.log_win) then return end
  local filename = vim.fn.fnamemodify(state.file, ':t')
  local line_range = state.start_line == state.end_line
    and tostring(state.start_line)
    or string.format('%d-%d', state.start_line, state.end_line)
  local status
  if loading then
    status = tostring(state.commit_count) .. ' ' .. spinner[state.spinner_idx]
  else
    status = tostring(state.commit_count)
  end
  vim.wo[state.log_win].statusline = string.format(
    ' %%#Function#Log%%* L%%#Number#%s%%* [%%#Special#%s%%*] %%#Comment#%s%%*',
    line_range, status, filename
  )
end

local function stop_spinner()
  if state.spinner_timer then
    vim.fn.timer_stop(state.spinner_timer)
    state.spinner_timer = nil
  end
end

local function start_spinner()
  stop_spinner()
  state.spinner_idx = 1
  update_log_statusline(true)
  state.spinner_timer = vim.fn.timer_start(50, function()
    if not state.log_win or not vim.api.nvim_win_is_valid(state.log_win) then
      stop_spinner()
      return
    end
    state.spinner_idx = (state.spinner_idx % #spinner) + 1
    update_log_statusline(true)
  end, { ['repeat'] = -1 })
end

local function highlight_commit_lines(buf, start_idx, lines)
  for i, line in ipairs(lines) do
    local hash_end = line:find(' ')
    if hash_end then
      vim.api.nvim_buf_add_highlight(buf, ns_id, 'Number', start_idx + i - 1, 0, hash_end - 1)
      local date_start = hash_end
      local date_end = hash_end + 19
      if #line >= date_end then
        vim.api.nvim_buf_add_highlight(buf, ns_id, 'Comment', start_idx + i - 1, date_start, date_end)
      end
    end
  end
end

local function kill_job()
  state.cancelled = true
  stop_spinner()
  if state.job then
    pcall(function() state.job:kill() end)
    state.job = nil
  end
  if state.diff_job then
    pcall(function() state.diff_job:kill() end)
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

local function set_buffer_lines(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function append_commit_line(rev)
  if not vim.api.nvim_buf_is_valid(state.log_buf) then return end
  local line = string.format('%s %s %s', rev.hash, rev.date, rev.message)
  vim.bo[state.log_buf].modifiable = true
  if state.commit_count == 0 then
    vim.api.nvim_buf_set_lines(state.log_buf, 0, -1, false, { line })
  else
    vim.api.nvim_buf_set_lines(state.log_buf, -1, -1, false, { line })
  end
  state.commit_count = state.commit_count + 1
  highlight_commit_lines(state.log_buf, state.commit_count - 1, { line })
  vim.bo[state.log_buf].modifiable = false
  update_log_statusline(true)
end

-- Load file content at a specific revision
local function load_file_content(rev_hash, callback)
  local cmd = { 'git', 'show', rev_hash .. ':' .. state.rel_file }
  state.job = vim.system(cmd, { text = true, cwd = state.repo_root }, function(result)
    vim.schedule(function()
      state.job = nil
      if state.cancelled then return end
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
  if state.cancelled then return end
  if not vim.api.nvim_buf_is_valid(state.log_buf) then
    kill_job()
    return
  end

  state.current_idx = state.current_idx + 1
  local idx = state.current_idx

  if idx > #state.revisions then
    -- Done
    stop_spinner()
    update_log_statusline(false)
    if state.commit_count == 0 then
      set_buffer_lines(state.log_buf, { '-- No commits found --' })
    end
    return
  end

  local rev = state.revisions[idx]
  local prev_block = state.blocks[idx - 1]

  load_file_content(rev.hash, function(lines)
    if state.cancelled then return end
    if not lines then
      -- File doesn't exist in this revision, stop here
      stop_spinner()
      update_log_statusline(false)
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
        append_commit_line(state.revisions[idx - 1])
      end
    end

    -- If block became empty, stop processing (matches IDEA's EMPTY_BLOCK break)
    if new_block:is_empty() then
      stop_spinner()
      update_log_statusline(false)
      return
    end

    -- If this is the last revision and block exists, show it (initial creation)
    if idx == #state.revisions then
      append_commit_line(rev)
    end

    -- Continue to next revision
    process_next_revision()
  end)
end

-- Get list of revisions for the file
local function load_revisions()
  local cmd = {
    'git', 'log',
    '--format=%h %ad %s',
    '--date=format:%Y-%m-%d %H:%M:%S',
    '--follow',
    '--', state.rel_file,
  }

  state.job = vim.system(cmd, { text = true, cwd = state.repo_root }, function(result)
    vim.schedule(function()
      state.job = nil
      if state.cancelled then return end
      if result.code ~= 0 or not result.stdout or result.stdout == '' then
        stop_spinner()
        update_log_statusline(false)
        set_buffer_lines(state.log_buf, { '-- No commits found --' })
        return
      end

      local lines = vim.split(result.stdout, '\n', { trimempty = true })
      state.revisions = {}
      for _, line in ipairs(lines) do
        local hash, rest = line:match('^(%x+)%s+(.*)$')
        if hash and rest then
          local date, message = rest:match('^([%d%-]+%s+[%d:]+)%s+(.*)$')
          if date then
            table.insert(state.revisions, {
              hash = hash,
              date = date,
              message = message or '',
            })
          end
        end
      end

      if #state.revisions == 0 then
        stop_spinner()
        update_log_statusline(false)
        set_buffer_lines(state.log_buf, { '-- No commits found --' })
        return
      end

      -- Load current file content as base
      local current_lines = vim.api.nvim_buf_get_lines(
        vim.fn.bufnr(state.file),
        0, -1, false
      )
      state.blocks[0] = Block.new(current_lines, state.start_line, state.end_line)

      -- Start processing revisions
      process_next_revision()
    end)
  end)
end

-- Generate unified diff between two block contents (IntelliJ's approach:
-- directly diff block.getBlockContent() from each revision, with line number offset)
local function generate_block_diff(old_block, new_block, rev)
  local old_lines = (old_block and not old_block:is_empty()) and old_block:get_content() or {}
  local new_lines = (new_block and not new_block:is_empty()) and new_block:get_content() or {}

  local old_text = #old_lines > 0 and (table.concat(old_lines, '\n') .. '\n') or ''
  local new_text = #new_lines > 0 and (table.concat(new_lines, '\n') .. '\n') or ''

  local diff_str = vim.diff(old_text, new_text, { algorithm = 'histogram', ctxlen = 3 })
  if not diff_str or diff_str == '' then
    return { '-- No changes in selection --' }
  end

  local diff_lines = vim.split(diff_str, '\n', { plain = true })
  if #diff_lines > 0 and diff_lines[#diff_lines] == '' then
    table.remove(diff_lines)
  end

  -- Offset @@ line numbers to reflect actual file positions (like IDEA's LINE_NUMBER_CONVERTOR)
  local old_offset = (old_block and not old_block:is_empty()) and (old_block.start_line - 1) or 0
  local new_offset = (new_block and not new_block:is_empty()) and (new_block.start_line - 1) or 0

  if old_offset > 0 or new_offset > 0 then
    for i, line in ipairs(diff_lines) do
      local prefix, os, oc, mid, ns, nc, rest =
        line:match('^(@@ %-)(%d+)(,?%d*) (%+)(%d+)(,?%d*) (@@.*)$')
      if prefix then
        diff_lines[i] = prefix .. (tonumber(os) + old_offset) .. oc
          .. ' ' .. mid .. (tonumber(ns) + new_offset) .. nc .. ' ' .. rest
      end
    end
  end

  return diff_lines
end

local function show_commit_diff()
  local cursor_line = vim.api.nvim_win_get_cursor(state.log_win)[1]
  local line = vim.api.nvim_buf_get_lines(state.log_buf, cursor_line - 1, cursor_line, false)[1]
  if not line then return end

  local commit = line:match('^(%x+)')
  if not commit then
    vim.notify('No commit hash found on this line', vim.log.levels.WARN)
    return
  end

  -- Find the revision index for this commit
  local rev_idx = nil
  for i, rev in ipairs(state.revisions) do
    if rev.hash == commit then
      rev_idx = i
      break
    end
  end
  if not rev_idx then return end

  local reuse_win = state.diff_win and vim.api.nvim_win_is_valid(state.diff_win)

  -- IntelliJ approach: diff block contents directly
  -- new_block = block at this revision (+ side), old_block = block at older revision (- side)
  local new_block = state.blocks[rev_idx]
  local old_block = state.blocks[rev_idx + 1]

  local rev = state.revisions[rev_idx]
  local lines = generate_block_diff(old_block, new_block, rev)

  if reuse_win then
    vim.bo[state.diff_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.diff_buf, 0, -1, false, lines)
    vim.bo[state.diff_buf].modifiable = false
  else
    state.diff_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.diff_buf].buftype = 'nofile'
    vim.bo[state.diff_buf].bufhidden = 'wipe'
    vim.bo[state.diff_buf].swapfile = false
    vim.bo[state.diff_buf].filetype = 'git'

    vim.api.nvim_buf_set_lines(state.diff_buf, 0, -1, false, lines)
    vim.bo[state.diff_buf].modifiable = false

    vim.api.nvim_set_current_win(state.log_win)
    vim.cmd('vsplit')
    state.diff_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.diff_win, state.diff_buf)
    vim.api.nvim_set_current_win(state.log_win)

    vim.keymap.set('n', 'q', function()
      if vim.api.nvim_win_is_valid(state.diff_win) then
        vim.api.nvim_win_close(state.diff_win, true)
      end
    end, { buffer = state.diff_buf, nowait = true })
  end

  local short_msg = rev and rev.message:sub(1, 50) or ''
  if rev and #rev.message > 50 then
    short_msg = short_msg .. '...'
  end
  vim.wo[state.diff_win].statusline = string.format(
    ' %%#Function#Diff%%* %%#Number#%s%%* %%#Comment#%s%%*',
    commit, short_msg
  )
end

local function setup_log_buffer_keymaps(buf)
  local opts = { buffer = buf, nowait = true }

  vim.keymap.set('n', '<CR>', show_commit_diff, opts)

  vim.keymap.set('n', 'J', function()
    local line_count = vim.api.nvim_buf_line_count(state.log_buf)
    local cursor_line = vim.api.nvim_win_get_cursor(state.log_win)[1]
    if cursor_line < line_count then
      vim.api.nvim_win_set_cursor(state.log_win, { cursor_line + 1, 0 })
      show_commit_diff()
    end
  end, opts)

  vim.keymap.set('n', 'K', function()
    local cursor_line = vim.api.nvim_win_get_cursor(state.log_win)[1]
    if cursor_line > 1 then
      vim.api.nvim_win_set_cursor(state.log_win, { cursor_line - 1, 0 })
      show_commit_diff()
    end
  end, opts)

  vim.keymap.set('n', 'q', function()
    kill_job()
    if state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) then
      vim.api.nvim_win_close(state.diff_win, true)
    end
    if state.log_win and vim.api.nvim_win_is_valid(state.log_win) then
      vim.api.nvim_win_close(state.log_win, true)
    end
  end, opts)
end

local function is_in_git_repo(file)
  local dir = vim.fn.fnamemodify(file, ':h')
  local result = vim.system({ 'git', '-C', dir, 'rev-parse', '--is-inside-work-tree' }, { text = true }):wait()
  return result.code == 0
end

local function get_relative_path(file)
  local dir = vim.fn.fnamemodify(file, ':h')
  local result = vim.system({ 'git', '-C', dir, 'ls-files', '--full-name', file }, { text = true }):wait()
  if result.code == 0 and result.stdout and result.stdout ~= '' then
    return vim.trim(result.stdout)
  end
  -- Fallback: get path relative to repo root
  result = vim.system({ 'git', '-C', dir, 'rev-parse', '--show-toplevel' }, { text = true }):wait()
  if result.code == 0 and result.stdout then
    local root = vim.trim(result.stdout)
    if file:sub(1, #root) == root then
      return file:sub(#root + 2)
    end
  end
  return vim.fn.fnamemodify(file, ':t')
end

local function get_repo_root(file)
  local dir = vim.fn.fnamemodify(file, ':h')
  local result = vim.system({ 'git', '-C', dir, 'rev-parse', '--show-toplevel' }, { text = true }):wait()
  if result.code == 0 and result.stdout then
    return vim.trim(result.stdout)
  end
  return dir
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

  if not is_in_git_repo(file) then
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
  state.rel_file = get_relative_path(file)
  state.repo_root = get_repo_root(file)
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

  start_spinner()
  setup_log_buffer_keymaps(state.log_buf)

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
