local Block = require('lu5je0.ext.git.line-log.block')
local ui = require('lu5je0.ext.git.line-log.ui')
local env_keeper = require('lu5je0.misc.env-keeper')

local M = {}

local hl_ns = vim.api.nvim_create_namespace('git_line_log_selected')

local state = {
  job = nil,
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
  -- block tracking data
  revisions = {}, -- list of {hash, full, date, message, author, file}
  blocks = {}, -- list of Block objects indexed by revision idx
  current_idx = 0,
  cancelled = false,
  -- diff mode: 'single' or 'dual' (vimdiff style)
  diff_mode = env_keeper.get('line_log_diff_mode', 'single'),
}

local function kill_job()
  state.cancelled = true
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
      -- IDEA's Block.tokenize keeps trailing empty line (skipLastEmptyLine=false)
      local lines = vim.split(result.stdout or '', '\n', { plain = true })
      callback(lines)
    end)
  end)
end

-- Parse git log output with --name-status into structured revision entries.
-- Merge commits without name-status lines get a default 'M\t<path>' status.
local function parse_revisions_with_status(stdout, default_path)
  local result = {}
  local current = nil
  for line in stdout:gmatch('[^\n]*') do
    if line:find('%z') then
      -- Commit line (contains NUL separator): flush previous if it had no status line
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
      current.status = line:sub(1, 1)
      current.file = line:match('\t(.+)$') or default_path
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

-- Collect revisions using IDEA's algorithm:
-- 1. git log --full-history --simplify-merges -- <file> (includes merge commits)
-- 2. When hitting an 'A' (add) commit, check rename via git show -M --follow
-- 3. If rename found, queue old path for further history
-- 4. Deduplicate via visited set
local function collect_revisions_async(head_commit, callback)
  local visited = {}
  local all_revisions = {}
  local queue = { { commit = head_commit, path = state.rel_file } }

  local function process_queue()
    if state.cancelled then
      return
    end
    if #queue == 0 then
      callback(all_revisions)
      return
    end

    local item = table.remove(queue, 1)
    local cmd = {
      'git', 'log', item.commit,
      '--format=%H %h%x00%ad%x00%s%x00%an',
      '--date=format:%Y-%m-%d %H:%M:%S',
      '--abbrev=8',
      '--name-status',
      '--full-history', '--simplify-merges',
      '--', item.path,
    }

    state.job = vim.system(cmd, { text = true, cwd = state.repo_root }, function(result)
      vim.schedule(function()
        state.job = nil
        if state.cancelled then
          return
        end
        if result.code ~= 0 or not result.stdout then
          process_queue()
          return
        end

        local entries = parse_revisions_with_status(result.stdout, item.path)
        local last_add_commit = nil

        for _, entry in ipairs(entries) do
          if not visited[entry.full] then
            visited[entry.full] = true
            all_revisions[#all_revisions + 1] = {
              hash = entry.hash,
              full = entry.full,
              date = entry.date,
              message = entry.message,
              author = entry.author,
              file = entry.file,
            }
            if entry.status == 'A' then
              last_add_commit = entry.full
              break
            end
          end
        end

        if last_add_commit then
          local show_cmd = {
            'git', 'show', '-M', '--follow', '--name-status',
            '--format=%H %h', last_add_commit, '--', item.path,
          }
          state.job = vim.system(show_cmd, { text = true, cwd = state.repo_root }, function(show_result)
            vim.schedule(function()
              state.job = nil
              if state.cancelled then
                return
              end
              if show_result.code == 0 and show_result.stdout then
                for line in show_result.stdout:gmatch('[^\n]+') do
                  if line:match('^R') and line:find('\t') then
                    local parts = vim.split(line, '\t', { plain = true })
                    if #parts >= 3 then
                      queue[#queue + 1] = { commit = last_add_commit, path = parts[2] }
                    end
                    break
                  end
                end
              end
              process_queue()
            end)
          end)
        else
          process_queue()
        end
      end)
    end)
  end

  process_queue()
end

-- Process next revision in the tracking loop
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
  ui.update_log_statusline(state, true)

  if idx > #state.revisions then
    ui.update_log_statusline(state, false)
    if state.commit_count == 0 then
      ui.set_buffer_lines(state.log_buf, { '-- No commits found --' })
    end
    return
  end

  local rev = state.revisions[idx]

  load_file_content(rev.full, rev.file, function(lines)
    if state.cancelled then
      return
    end
    if not lines then
      ui.update_log_statusline(state, false)
      return
    end

    local prev_block = state.blocks[idx - 1]:create_previous_block(lines)
    state.blocks[idx] = prev_block

    local changed = not state.blocks[idx - 1]:content_equals(prev_block)

    if changed and idx > 1 then
      ui.append_commit_line(state, state.revisions[idx - 1])
    end

    if prev_block:is_empty() then
      ui.update_log_statusline(state, false)
      return
    end

    if idx == #state.revisions then
      ui.append_commit_line(state, rev)
    end

    process_next_revision()
  end)
end

-- Start revision collection and block tracking
local function load_revisions()
  state.job = vim.system({ 'git', 'rev-parse', 'HEAD' }, { text = true, cwd = state.repo_root }, function(result)
    vim.schedule(function()
      state.job = nil
      if state.cancelled then
        return
      end
      if result.code ~= 0 then
        ui.update_log_statusline(state, false)
        ui.set_buffer_lines(state.log_buf, { '-- Not in a git repository --' })
        return
      end

      local head = (result.stdout or ''):match('%x+')
      if not head then
        ui.update_log_statusline(state, false)
        ui.set_buffer_lines(state.log_buf, { '-- No commits found --' })
        return
      end

      collect_revisions_async(head, function(revisions)
        if state.cancelled then
          return
        end
        state.revisions = revisions

        if #revisions == 0 then
          ui.update_log_statusline(state, false)
          ui.set_buffer_lines(state.log_buf, { '-- No commits found --' })
          return
        end

        -- Initial block from buffer content
        local current_lines = vim.api.nvim_buf_get_lines(vim.fn.bufnr(state.file), 0, -1, false)
        -- IDEA's Block.tokenize keeps trailing empty line for files ending with \n
        current_lines[#current_lines + 1] = ''
        state.blocks[0] = Block.new(current_lines, state.start_line, state.end_line)

        process_next_revision()
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
  for _, win in ipairs({ state.diff_win2, state.diff_win, state.log_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
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
  state.source_buf = vim.api.nvim_get_current_buf()

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
  ui.setup_log_buffer_keymaps(state, kill_job, toggle_diff_mode)

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
