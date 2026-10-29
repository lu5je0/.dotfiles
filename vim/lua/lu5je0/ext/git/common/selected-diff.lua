local Block = require('lu5je0.ext.git.line-log.block')
local ui = require('lu5je0.ext.git.common.ui')
local tree = require('lu5je0.ext.git.common.tree')
local project_ui = require('lu5je0.ext.git.project-log.ui')
local config = require('lu5je0.ext.git.config')

local M = {}

local function escape(text)
  return (text or ''):gsub('%%', '%%%%')
end

-- Show the prepared net changes in a shared file tree and diff panes.
function M.open(opts)
  local origin_win = vim.api.nvim_get_current_win()
  local mode = vim.fn.mode()
  if mode == 'v' or mode == 'V' or mode == '\22' then
    vim.cmd.normal { args = { vim.api.nvim_replace_termcodes('<Esc>', true, false, true) }, bang = true }
  end
  vim.cmd.tabnew()
  local state = {
    tab = vim.api.nvim_get_current_tabpage(),
    log_win = vim.api.nvim_get_current_win(),
    log_buf = vim.api.nvim_get_current_buf(),
    mode = opts.mode or 'single',
    changes_only = opts.changes_only == true,
    index = 1,
    entries = {},
    file_groups = {},
    commits = {},
    display_items = {},
    render = project_ui.render_log,
    tree_opts = {
      status_hl_fn = function()
        return 'Type'
      end,
    },
    generation = 0,
    closed = false,
  }
  local render, move, focus_entry

  local function cancel()
    state.generation = state.generation + 1
    if state.job then
      pcall(state.job.kill, state.job)
      state.job = nil
    end
  end

  local function cleanup()
    if opts.cleanup then
      opts.cleanup()
    end
  end

  local function valid()
    return not state.closed and vim.api.nvim_win_is_valid(state.log_win) and vim.api.nvim_buf_is_valid(state.log_buf)
  end

  local function runner()
    cancel()
    local generation = state.generation
    return function(args, cwd, callback, system_opts)
      system_opts = vim.tbl_extend('force', system_opts or {}, { cwd = cwd, text = true })
      state.job = vim.system(args, system_opts, function(result)
        vim.schedule(function()
          if not valid() or generation ~= state.generation then
            return
          end
          state.job = nil
          callback(result)
        end)
      end)
    end
  end

  local function close()
    state.closed = true
    cancel()
    cleanup()
    if vim.api.nvim_tabpage_is_valid(state.tab) then
      vim.api.nvim_set_current_tabpage(state.tab)
      if #vim.api.nvim_list_tabpages() > 1 then
        vim.cmd.tabclose()
      else
        vim.cmd.bdelete { bang = true }
      end
    end
    if vim.api.nvim_win_is_valid(origin_win) then
      vim.api.nvim_set_current_win(origin_win)
    end
  end

  local function setup_buffer(buf, ft)
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = ft
    local map = { buffer = buf, nowait = true }
    vim.keymap.set('n', 'q', close, map)
    vim.keymap.set('n', 'd', function()
      state.mode = state.mode == 'single' and 'dual' or 'single'
      render()
    end, map)
    vim.keymap.set('n', 'c', function()
      state.changes_only = not state.changes_only
      render()
    end, map)
    for _, pair in ipairs { { ']c', 1, true }, { '[c', -1, true }, { ']f', 1, false }, { '[f', -1, false } } do
      if not (opts.net_diff and pair[3]) then
        vim.keymap.set('n', pair[1], function()
          move(pair[2], pair[3])
        end, map)
      end
    end
  end

  setup_buffer(state.log_buf, 'git')
  vim.w[state.log_win].git_selected_diff_tree = true
  vim.wo[state.log_win].cursorline = true
  vim.wo[state.log_win].cursorlineopt = 'both'
  vim.wo[state.log_win].wrap = false
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = state.log_buf,
    once = true,
    callback = function()
      state.closed = true
      cancel()
      cleanup()
    end,
  })

  local function entry_under_cursor()
    local item = tree.item_under_cursor(state)
    if not item or item.type ~= 'file' then
      return nil
    end
    return state.commits[item.commit_idx].files[item.file_idx].entry_idx
  end

  local function preview(force)
    if not state.ready then
      return
    end
    local index = entry_under_cursor()
    if index and state.entries[index].file_group_idx == state.entries[state.index].file_group_idx then
      index = state.index
    end
    if index and (force or index ~= state.index) then
      state.index = index
      render()
    end
  end

  local map = { buffer = state.log_buf, nowait = true }
  local function activate()
    if not tree.open_node(state) then
      preview(true)
    end
  end
  vim.keymap.set('n', '<CR>', activate, map)
  vim.keymap.set('n', 'l', activate, map)
  vim.keymap.set('n', 'h', function()
    tree.close_parent_node(state)
  end, map)
  vim.keymap.set('n', 'H', function()
    tree.close_commit_node(state)
  end, map)
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = state.log_buf,
    callback = function()
      if vim.api.nvim_get_current_win() == state.log_win then
        preview(false)
      end
    end,
  })

  local function ensure_preview()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      return
    end
    vim.api.nvim_win_call(state.log_win, function()
      vim.cmd('rightbelow vsplit')
      state.win = vim.api.nvim_get_current_win()
      state.buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(state.win, state.buf)
      setup_buffer(state.buf, 'git')
      vim.w[state.win].git_selected_diff = true
      vim.wo[state.win].number = true
      vim.wo[state.win].relativenumber = false
      vim.wo[state.win].statuscolumn = ''
      vim.api.nvim_win_set_width(state.log_win, math.min(math.max(config.log_width, 25), math.floor(vim.o.columns / 3)))
    end)
  end

  local function load_source(source, run, done)
    if not source then
      done {}
    elseif source.worktree then
      local ok, lines = pcall(vim.fn.readfile, source.worktree)
      if not ok then
        done(nil, tostring(lines))
        return
      end
      for _, line in ipairs(lines) do
        if line:find('\n', 1, true) then
          done(nil, 'Binary file (no text preview)')
          return
        end
      end
      done(lines)
    else
      local args = { 'git' }
      if source.git_dir then
        args[#args + 1] = '--git-dir=' .. source.git_dir
      end
      vim.list_extend(args, { 'show', source.rev .. ':' .. source.path })
      run(args, source.repo_root, function(result)
        if result.code ~= 0 then
          done(nil, result.stderr or 'Failed to load file')
          return
        end
        if (result.stdout or ''):find('\0', 1, true) then
          done(nil, 'Binary file (no text preview)')
          return
        end
        local lines = vim.split(result.stdout or '', '\n', { plain = true })
        if lines[#lines] == '' then
          table.remove(lines)
        end
        done(lines)
      end)
    end
  end

  local function load(entry, run, done)
    if entry.loaded then
      done()
      return
    end
    load_source(entry.old_source, run, function(old_lines, err)
      if err then
        entry.error, entry.loaded = err, true
        done()
        return
      end
      load_source(entry.new_source, run, function(new_lines, new_err)
        entry.error = new_err
        if not new_err then
          entry.old_block = Block.new(old_lines, 1, #old_lines)
          entry.new_block = Block.new(new_lines, 1, #new_lines)
        end
        entry.loaded = true
        done()
      end)
    end)
  end

  local function status(entry)
    if opts.net_diff then
      return string.format(' Selected Diff net | %s | [f/]f file D mode d context q back', escape(entry.path))
    end
    local group = state.file_groups[entry.file_group_idx]
    local position = vim.fn.index(group.indices, state.index) + 1
    return string.format(' Selected Diff %s | %d/%d %s | D mode [c/]c commit [f/]f file q back', escape(entry.path), position, #group.indices, escape(entry.hash))
  end

  local function single(entry)
    if state.win2 and vim.api.nvim_win_is_valid(state.win2) then
      vim.api.nvim_win_close(state.win2, true)
    end
    state.win2, state.buf2 = nil, nil
    vim.wo[state.win].diff = false
    vim.wo[state.win].scrollbind = false
    vim.wo[state.win].foldenable = false
    vim.bo[state.buf].filetype = 'git'
    local lines = {}
    for _, index in ipairs(state.file_groups[entry.file_group_idx].indices) do
      local patch_entry = state.entries[index]
      patch_entry.header_line = #lines + 1
      lines[#lines + 1] = 'commit ' .. patch_entry.hash .. ' ' .. patch_entry.message
      lines[#lines + 1] = 'file ' .. patch_entry.path
      if patch_entry.old_path and patch_entry.old_path ~= patch_entry.path then
        local action = patch_entry.change_type == 'C' and 'copy' or 'rename'
        lines[#lines + 1] = action .. ' from ' .. patch_entry.old_path
        lines[#lines + 1] = action .. ' to ' .. patch_entry.path
      end
      local patch = patch_entry.error and vim.split(patch_entry.error, '\n', { plain = true })
        or Block.generate_diff(patch_entry.old_block, patch_entry.new_block, patch_entry.old_path, patch_entry.path, state.changes_only and { ctxlen = 3 } or nil)
      vim.list_extend(lines, patch)
      lines[#lines + 1] = ''
    end
    ui.set_buffer_lines(state.buf, lines)
    vim.wo[state.win].statusline = status(entry)
    vim.api.nvim_win_set_cursor(state.win, { entry.header_line, 0 })
  end

  local function dual(entry)
    if not state.win2 or not vim.api.nvim_win_is_valid(state.win2) then
      vim.api.nvim_win_call(state.win, function()
        vim.cmd('rightbelow vsplit')
        state.win2 = vim.api.nvim_get_current_win()
        state.buf2 = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_win_set_buf(state.win2, state.buf2)
        setup_buffer(state.buf2, 'git')
        vim.w[state.win2].git_selected_diff = true
        vim.wo[state.win2].number = true
        vim.wo[state.win2].relativenumber = false
        vim.wo[state.win2].statuscolumn = ''
      end)
    end
    local old = entry.old_block and entry.old_block:get_content() or {}
    local new = entry.new_block and entry.new_block:get_content() or {}
    if entry.error then
      old = vim.split(entry.error, '\n', { plain = true })
      new = old
    end
    ui.set_buffer_lines(state.buf, old)
    ui.set_buffer_lines(state.buf2, new)
    for _, side in ipairs { { state.win, state.buf, entry.old_path }, { state.win2, state.buf2, entry.path } } do
      vim.bo[side[2]].filetype = vim.filetype.match { filename = side[3] or entry.path } or ''
      vim.wo[side[1]].diff = true
      vim.wo[side[1]].scrollbind = true
      vim.wo[side[1]].wrap = false
      vim.wo[side[1]].foldmethod = 'diff'
      vim.wo[side[1]].foldlevel = 0
      vim.wo[side[1]].foldenable = state.changes_only == true
    end
    vim.wo[state.win].statusline = ' OLD (parent) |' .. status(entry)
    vim.wo[state.win2].statusline = ' NEW |' .. status(entry)
    vim.api.nvim_win_call(state.win, function()
      vim.cmd.diffupdate()
    end)
  end

  render = function()
    if not valid() or not state.ready then
      return
    end
    ensure_preview()
    local entry = state.entries[state.index]
    vim.wo[state.win].statusline = ' Selected Diff loading ' .. escape(entry.path)
    local run = runner()
    if state.mode == 'dual' then
      load(entry, run, function()
        if valid() then
          dual(entry)
        end
      end)
    else
      local indices = state.file_groups[entry.file_group_idx].indices
      local generation = state.generation
      local function load_next(position)
        if not valid() or generation ~= state.generation then
          return
        end
        if position > #indices then
          single(entry)
          return
        end
        load(state.entries[indices[position]], run, function()
          vim.schedule(function()
            load_next(position + 1)
          end)
        end)
      end
      load_next(1)
    end
  end

  focus_entry = function()
    local entry = state.entries[state.index]
    local commit = state.commits[entry.commit_idx]
    local function find_row()
      for line, item in ipairs(state.display_items) do
        if item.type == 'file' and state.commits[item.commit_idx].files[item.file_idx].file_group_idx == entry.file_group_idx then
          return line
        end
      end
    end
    local line = find_row()
    if not line then
      commit.expanded = true
      tree.expand_all_dirs(commit)
      project_ui.render_log(state)
      line = find_row()
    end
    if line then
      vim.api.nvim_win_set_cursor(state.log_win, { line, 0 })
    end
  end

  move = function(delta, by_commit)
    if not state.ready then
      return
    end
    local entry = state.entries[state.index]
    local group = state.file_groups[entry.file_group_idx]
    local target
    if by_commit then
      target = group.indices[vim.fn.index(group.indices, state.index) + 1 + delta]
    else
      local next_group = state.file_groups[entry.file_group_idx + delta]
      target = next_group and next_group.indices[1]
    end
    if target then
      state.index = target
      focus_entry()
      render()
    end
  end

  ui.set_buffer_lines(state.log_buf, { '-- Loading selected commits... --' })
  local function prepared(entries, err)
    if not valid() then
      return
    end
    if err or #entries == 0 then
      local label = string.format('Selected %d commits', opts.commit_count or 0)
      local message = err or (opts.net_diff and '-- No net changes --' or '-- No selected commits --')
      ui.set_buffer_lines(state.log_buf, vim.list_extend({ label }, vim.split(message, '\n', { plain = true })))
      vim.wo[state.log_win].statusline = err and ' Selected Diff | Cannot merge selected commits' or string.format(' Selected Diff %d commits / 0 files', opts.commit_count or 0)
      cleanup()
      return
    end
    state.entries = entries
    local commits_by_hash, groups_by_path = {}, {}
    local files = {}
    state.commits[1] = {
      hash = 'selection',
      short_hash = 'Selected',
      message = '',
      date = '',
      author = '',
      files = files,
      expanded = true,
      expanded_dirs = {},
    }
    for i, entry in ipairs(entries) do
      commits_by_hash[entry.hash] = true
      local group_idx = groups_by_path[entry.path]
      if not group_idx then
        group_idx = #state.file_groups + 1
        groups_by_path[entry.path] = group_idx
        state.file_groups[group_idx] = { path = entry.path, indices = {} }
        files[group_idx] = {
          path = entry.path,
          status = entry.change_type or 'M',
          entry_idx = i,
          file_group_idx = group_idx,
        }
      end
      local file = files[group_idx]
      if file.status ~= (entry.change_type or 'M') then
        file.status = 'M'
      end
      if entry.old_path and entry.old_path ~= entry.path then
        file.old_path = entry.old_path
      end
      entry.commit_idx, entry.file_group_idx = 1, group_idx
      table.insert(state.file_groups[group_idx].indices, i)
    end
    local commit_count = opts.commit_count or vim.tbl_count(commits_by_hash)
    state.commits[1].message = string.format('%d commits', commit_count)
    for _, commit in ipairs(state.commits) do
      tree.expand_all_dirs(commit)
    end
    project_ui.render_log(state)
    state.ready = true
    vim.wo[state.log_win].statusline = string.format(' Selected Diff %d commits / %d files | l open h fold q back', commit_count, #files)
    focus_entry()
    render()
  end
  if opts.prepare then
    opts.prepare(runner(), prepared)
  else
    prepared(opts.entries)
  end
  return state
end

return M
