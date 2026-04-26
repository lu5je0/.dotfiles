local core = require('lu5je0.ext.git.project-log.core')
local diff = require('lu5je0.ext.git.project-log.diff')
local help = require('lu5je0.ext.git.common.help')
local common_ui = require('lu5je0.ext.git.common.ui')
local scheduler = require('lu5je0.ext.git.common.scheduler')
local tree = require('lu5je0.ext.git.common.tree')
local ui = require('lu5je0.ext.git.project-log.ui')
local env_keeper = require('lu5je0.misc.env-keeper')

local M = {}

local DEFAULT_COMMIT_LIMIT = 1000

local state = {
  session = 0,
  job = nil,
  status_job = nil,
  diff_job = nil,
  diff_job2 = nil,
  log_buf = nil,
  log_win = nil,
  diff_buf = nil,
  diff_buf2 = nil,
  diff_win = nil,
  diff_win2 = nil,
  repo_root = nil,
  commits = {},
  display_items = {},
  preview_key = nil,
  diff_mode = env_keeper.get('line_log_diff_mode', 'single'),
  diff_changes_only = env_keeper.get('line_log_diff_changes_only', false),
  closing_diff_windows = false,
  render = function(s) ui.render_log(s) end,
  tree_opts = { status_hl_fn = function() return 'Type' end },
  commit_limit = DEFAULT_COMMIT_LIMIT,
  limited = false,
}

local function kill_job(job_name)
  if state[job_name] then
    pcall(function()
      state[job_name]:kill()
    end)
    state[job_name] = nil
  end
end

local function kill_jobs()
  kill_job('job')
  kill_job('status_job')
  diff.kill_jobs(state)
end

local function is_active_session(session)
  return state.session == session
end

local function cleanup()
  kill_jobs()
  diff.close_windows(state)
  common_ui.clear_active_file(state)
  if state.render_timer then
    state.render_timer:stop()
    state.render_timer:close()
    state.render_timer = nil
  end
  state.session = state.session + 1
  state.log_buf = nil
  state.log_win = nil
  state.commits = {}
  state.display_items = {}
  state.preview_key = nil
  state.limited = false
  state.commit_limit = DEFAULT_COMMIT_LIMIT
end

local function get_commit_and_file(item)
  if not item then
    return nil, nil
  end
  local commit = state.commits[item.commit_idx]
  local file = commit and commit.files[item.file_idx] or nil
  return commit, file
end

local function make_preview_key(commit, file)
  if not commit or not file then
    return nil
  end
  return table.concat({
    commit.hash,
    file.status,
    file.old_path or '',
    file.path,
    state.diff_mode,
    tostring(state.diff_changes_only),
  }, '\30')
end

local function has_diff_window()
  return state.diff_win and vim.api.nvim_win_is_valid(state.diff_win)
end

local function show_file_diff(auto_preview)
  if auto_preview and not has_diff_window() then
    return false
  end
  local item = tree.item_under_cursor(state)
  if not item or item.type ~= 'file' then
    return false
  end
  local commit, file = get_commit_and_file(item)
  if not commit or not file then
    return false
  end
  local preview_key = make_preview_key(commit, file)
  if state.preview_key == preview_key then
    common_ui.update_active_file_highlight(state)
    return true
  end
  state.preview_key = preview_key
  state.active_file = { commit_idx = item.commit_idx, file_idx = item.file_idx }
  common_ui.update_active_file_highlight(state)
  if state.diff_mode == 'dual' then
    diff.show_dual(state, commit, file)
  else
    diff.show_single(state, commit, file)
  end
  return true
end

local function activate_item()
  if tree.open_node(state) then
    return
  end
  state.preview_key = nil
  show_file_diff()
end

local function close_all()
  if state.log_win and vim.api.nvim_win_is_valid(state.log_win) then
    pcall(vim.api.nvim_win_close, state.log_win, true)
  end
  cleanup()
end

local load_commits

local function reload_all()
  kill_jobs()
  diff.close_windows(state)
  if state.render_timer then
    state.render_timer:stop()
    state.render_timer:close()
    state.render_timer = nil
  end
  state.session = state.session + 1
  state.commits = {}
  state.display_items = {}
  state.preview_key = nil
  state.commit_limit = nil
  state.limited = false
  ui.set_buffer_lines(state.log_buf, { '-- Loading all commits... --' })
  vim.cmd('messages clear')
  load_commits()
end

local function setup_keymaps()
  local opts = { buffer = state.log_buf, nowait = true }
  local preview_scheduler = scheduler.create(function()
    show_file_diff(true)
  end)

  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = state.log_buf,
    callback = function()
      common_ui.sync_active_file_highlight(state)
      preview_scheduler.request()
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = state.log_buf,
    once = true,
    callback = preview_scheduler.close,
  })

  vim.keymap.set('n', 'l', activate_item, opts)
  vim.keymap.set('n', 'h', function()
    tree.close_parent_node(state)
  end, opts)
  vim.keymap.set('n', 'H', function()
    tree.close_commit_node(state)
  end, opts)
  vim.keymap.set('n', '<cr>', activate_item, opts)
  vim.keymap.set('n', 'd', function()
    state.diff_changes_only = not state.diff_changes_only
    env_keeper.set('line_log_diff_changes_only', state.diff_changes_only)
    ui.update_statusline(state, false)
    vim.notify('Changes only: ' .. (state.diff_changes_only and 'on' or 'off'), vim.log.levels.INFO)
    state.preview_key = nil
    show_file_diff(true)
  end, opts)
  vim.keymap.set('n', 'D', function()
    state.diff_mode = state.diff_mode == 'single' and 'dual' or 'single'
    env_keeper.set('line_log_diff_mode', state.diff_mode)
    ui.update_statusline(state, false)
    vim.notify('Diff mode: ' .. state.diff_mode, vim.log.levels.INFO)
    state.preview_key = nil
    show_file_diff(true)
  end, opts)
  vim.keymap.set('n', 'a', function()
    if state.limited then
      reload_all()
    end
  end, opts)
  vim.keymap.set('n', 'gf', function()
    local item = tree.item_under_cursor(state)
    if not item or item.type ~= 'file' then
      return
    end
    local _, file = get_commit_and_file(item)
    if not file then
      return
    end
    local target_win
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= state.log_win and win ~= state.diff_win and win ~= state.diff_win2 then
        local buf = vim.api.nvim_win_get_buf(win)
        local bt = vim.bo[buf].buftype
        if bt == '' then
          target_win = win
          break
        end
      end
    end
    if target_win then
      vim.api.nvim_set_current_win(target_win)
    else
      vim.cmd('wincmd p')
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(state.repo_root .. '/' .. file.path))
  end, opts)
  vim.keymap.set('n', 'x', function()
    if not state.log_win or not vim.api.nvim_win_is_valid(state.log_win) then
      return
    end
    local total = vim.o.lines
    local threshold = math.floor(total * 0.7)
    local current = vim.api.nvim_win_get_height(state.log_win)
    if current >= threshold then
      vim.api.nvim_win_set_height(state.log_win, math.floor(total * 0.5))
    else
      vim.api.nvim_win_set_height(state.log_win, math.floor(total * 0.9))
    end
  end, opts)
  vim.keymap.set('n', '?', function()
    help.show_help('Help', {
      'Project Log Keymaps',
      '',
      '  l/<CR>  Open node / show diff',
      '  h       Fold parent node',
      '  H       Fold commit',
      '  d       Toggle changes-only',
      '  D       Toggle diff mode: single / dual',
      '  a       Load all commits (when limited)',
      '  gf      Open file',
      '  x       Toggle window height',
      '  ?       Show this help',
      '  q       Close',
    })
  end, opts)
end

load_commits = function()
  local session = state.session
  ui.update_statusline(state, true)

  local log_args = {
    'git', 'log', '--graph',
    '--date=format:%Y-%m-%d %H:%M:%S',
    '--pretty=format:%x1e%H%x00%h%x00%ad%x00%an%x00%s%x00%P',
    '--name-status', '--find-renames', '--find-copies',
  }

  local streaming = state.commit_limit == nil

  if state.commit_limit then
    log_args[#log_args + 1] = '--max-count=' .. (state.commit_limit + 1)
  end

  log_args[#log_args + 1] = '--'
  log_args[#log_args + 1] = '.'

  -- git status in parallel
  state.status_job = vim.system({
    'git', 'status', '--porcelain=v1', '-z', '--untracked-files=all',
  }, { text = true, cwd = state.repo_root }, function(status_result)
    vim.schedule(function()
      if not is_active_session(session) then
        return
      end
      state.status_job = nil
      local local_files = status_result.code == 0 and core.parse_status(status_result.stdout or '') or {}
      if #local_files > 0 then
        table.insert(state.commits, 1, {
          hash = 'local-change',
          short_hash = 'local',
          date = 'uncommitted',
          author = '',
          message = 'local change',
          files = local_files,
          expanded = false,
          expanded_dirs = {},
          local_change = true,
        })
        if streaming then
          ui.render_log(state)
          ui.update_statusline(state, true)
        end
      end
    end)
  end)

  if streaming then
    -- streaming mode for load-all
    local parser = core.create_log_parser()
    local dirty = false
    state.render_timer = vim.uv.new_timer()

    local function flush_render()
      if not is_active_session(session) then
        return
      end
      if dirty then
        dirty = false
        ui.render_log(state)
        ui.update_statusline(state, true)
      end
    end

    state.render_timer:start(50, 50, vim.schedule_wrap(flush_render))

    state.job = vim.system(log_args, {
      cwd = state.repo_root,
      stdout = function(_, chunk)
        if not chunk or not is_active_session(session) then
          return
        end
        local new_commits = parser:feed(chunk)
        if #new_commits > 0 then
          for _, c in ipairs(new_commits) do
            state.commits[#state.commits + 1] = c
          end
          dirty = true
        end
      end,
    }, function(result)
      vim.schedule(function()
        if state.render_timer then
          state.render_timer:stop()
          state.render_timer:close()
          state.render_timer = nil
        end
        if not is_active_session(session) then
          return
        end
        state.job = nil
        if result.code ~= 0 then
          if #state.commits == 0 then
            ui.set_buffer_lines(state.log_buf, { '-- Failed to load project log --', result.stderr or '' })
          end
          ui.update_statusline(state, false)
          return
        end
        local tail = parser:finish()
        for _, c in ipairs(tail) do
          state.commits[#state.commits + 1] = c
        end
        ui.render_log(state)
        ui.update_statusline(state, false)
      end)
    end)
  else
    -- non-streaming mode for limited load
    state.job = vim.system(log_args, { text = true, cwd = state.repo_root }, function(result)
      vim.schedule(function()
        if not is_active_session(session) then
          return
        end
        state.job = nil
        if result.code ~= 0 then
          if #state.commits == 0 then
            ui.set_buffer_lines(state.log_buf, { '-- Failed to load project log --', result.stderr or '' })
          end
          ui.update_statusline(state, false)
          return
        end
        local commits = core.parse_log(result.stdout)
        if #commits > state.commit_limit then
          state.limited = true
          for i = 1, state.commit_limit do
            state.commits[#state.commits + 1] = commits[i]
          end
          vim.notify(
            string.format("Loaded %d commits (more available, press 'a' to load all)", state.commit_limit),
            vim.log.levels.INFO
          )
        else
          for _, c in ipairs(commits) do
            state.commits[#state.commits + 1] = c
          end
        end
        ui.render_log(state)
        ui.update_statusline(state, false)
      end)
    end)
  end
end

function M.show()
  local start_path = vim.fn.expand('%:p')
  if start_path == '' then
    start_path = vim.fn.getcwd()
  end

  local repo_root = vim.fs.root(start_path, '.git')
  if not repo_root then
    vim.notify('Not in a git repository', vim.log.levels.WARN)
    return
  end

  cleanup()
  state.session = state.session + 1
  state.repo_root = repo_root

  state.log_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.log_buf].buftype = 'nofile'
  vim.bo[state.log_buf].bufhidden = 'wipe'
  vim.bo[state.log_buf].swapfile = false
  vim.bo[state.log_buf].filetype = 'git'
  ui.set_buffer_lines(state.log_buf, { '-- Loading project log... --' })

  local height = math.floor(vim.api.nvim_win_get_height(0) * 0.5)
  vim.cmd('botright split')
  state.log_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.log_win, state.log_buf)
  vim.api.nvim_win_set_height(state.log_win, height)

  setup_keymaps()
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = state.log_buf,
    once = true,
    callback = cleanup,
  })

  load_commits()
end

return M
