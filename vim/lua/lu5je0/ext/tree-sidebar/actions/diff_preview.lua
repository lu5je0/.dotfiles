local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')
local ui = require('lu5je0.core.ui')
local env_keeper = require('lu5je0.misc.env-keeper')

local M = {}

-- Diff windows/buffers live in per-tab state.diff_preview so two tabs
-- can each have their own diff visible without one overwriting the
-- other's window handles.

-- ── helpers ────────────────────────────────────────────────────────────

-- Quick binary heuristic: NUL byte in first 8KB.
local function bytes_look_binary(data)
  return data and data:find('\0', 1, true) ~= nil
end

local function read_worktree(abs_path, max_bytes)
  if vim.fn.filereadable(abs_path) ~= 1 then
    return { lines = {}, kind = 'missing' }
  end
  local stat = vim.uv.fs_stat(abs_path)
  if stat and stat.size and stat.size > max_bytes then
    return { lines = { string.format('[file too large: %d bytes, limit %d]', stat.size, max_bytes) }, kind = 'too_large' }
  end
  local fd = vim.uv.fs_open(abs_path, 'r', 438)
  if not fd then
    return { lines = {}, kind = 'missing' }
  end
  local probe = vim.uv.fs_read(fd, 8192, 0)
  vim.uv.fs_close(fd)
  if bytes_look_binary(probe) then
    return { lines = { '[binary file]' }, kind = 'binary' }
  end
  return { lines = vim.fn.readfile(abs_path), kind = 'text' }
end

local function git_show_to_lines(spec, max_bytes, cb)
  -- spec is a `git show` argument like 'HEAD:path' or ':path'
  vim.system({ 'git', 'show', spec }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 or not result.stdout then
        cb({ lines = {}, kind = 'missing' })
        return
      end
      if #result.stdout > max_bytes then
        cb({ lines = { string.format('[file too large: %d bytes, limit %d]', #result.stdout, max_bytes) }, kind = 'too_large' })
        return
      end
      if bytes_look_binary(result.stdout:sub(1, 8192)) then
        cb({ lines = { '[binary file]' }, kind = 'binary' })
        return
      end
      local lines = vim.split(result.stdout, '\n', { plain = true })
      if #lines > 0 and lines[#lines] == '' then
        table.remove(lines)
      end
      cb({ lines = lines, kind = 'text' })
    end)
  end)
end

-- ── short HEAD cache ───────────────────────────────────────────────────

local _short_head_cache = {}
local function get_short_head(cwd, cb)
  if _short_head_cache[cwd] ~= nil then
    cb(_short_head_cache[cwd])
    return
  end
  vim.system({ 'git', 'rev-parse', '--short', 'HEAD' }, { text = true }, function(result)
    vim.schedule(function()
      local hash = ''
      if result.code == 0 and result.stdout then
        hash = (result.stdout:gsub('%s+$', ''))
      end
      _short_head_cache[cwd] = hash
      cb(hash)
    end)
  end)
end

function M.invalidate_short_head_cache()
  _short_head_cache = {}
end

-- ── diff target resolution ─────────────────────────────────────────────

--- Resolve what to put in the left/right diff buffers based on which section
--- the item belongs to.
---
--- Returns: { left = source, right = source, left_title = string, right_title = string }
--- where source = { kind = 'git_show'|'worktree'|'empty', spec = string|nil }
function M.resolve_diff_targets(item)
  local node = item.node
  local rel_path = node.rel_path or node.abs_path:sub(#vim.fn.getcwd() + 2)
  local section = item.section or node.section
  local xy = node.xy or '  '

  if section == 'untracked' or xy == '??' then
    return {
      left  = { kind = 'empty' },
      right = { kind = 'worktree', path = node.abs_path },
      left_title = ' (none) ',
      right_title = ' Working Tree ',
    }
  elseif section == 'staged' then
    return {
      left  = { kind = 'git_show', spec = 'HEAD:' .. rel_path },
      right = { kind = 'git_show', spec = ':' .. rel_path },
      left_title = ' HEAD ',
      right_title = ' Index ',
    }
  elseif section == 'unstaged' then
    return {
      left  = { kind = 'git_show', spec = ':' .. rel_path },
      right = { kind = 'worktree', path = node.abs_path },
      left_title = ' Index ',
      right_title = ' Working Tree ',
    }
  end
  if section == 'stash' and node.stash_ref then
    return {
      left  = { kind = 'git_show', spec = node.stash_ref .. '^:' .. rel_path },
      right = { kind = 'git_show', spec = node.stash_ref .. ':' .. rel_path },
      left_title = ' Parent ',
      right_title = ' ' .. node.stash_ref .. ' ',
    }
  end

  -- 'changes' (combined view) and any unknown section fall back to HEAD↔WT
  return {
    left  = { kind = 'git_show', spec = 'HEAD:' .. rel_path },
    right = { kind = 'worktree', path = node.abs_path },
    left_title = ' HEAD ',
    right_title = ' Working Tree ',
  }
end

local function fetch_source(source, max_bytes, cb)
  if source.kind == 'empty' then
    cb({ lines = {}, kind = 'text' })
  elseif source.kind == 'worktree' then
    cb(read_worktree(source.path, max_bytes))
  elseif source.kind == 'git_show' then
    git_show_to_lines(source.spec, max_bytes, cb)
  end
end

-- ── window management ──────────────────────────────────────────────────

local function dp(ts)
  return (ts or state.tab()).diff_preview
end

local function close_for(ts)
  local d = dp(ts)
  if d.win_left and vim.api.nvim_win_is_valid(d.win_left) then
    vim.api.nvim_win_close(d.win_left, true)
  end
  if d.win_right and vim.api.nvim_win_is_valid(d.win_right) then
    vim.api.nvim_win_close(d.win_right, true)
  end
  if d.win_single and vim.api.nvim_win_is_valid(d.win_single) then
    vim.api.nvim_win_close(d.win_single, true)
  end
  d.win_left = nil
  d.win_right = nil
  d.buf_left = nil
  d.buf_right = nil
  d.win_single = nil
  d.buf_single = nil
end

function M.close()
  close_for(state.tab())
end

-- ── mode (single | dual) ───────────────────────────────────────────────

local VALID_MODES = { single = true, dual = true }

function M.get_mode()
  local mode = env_keeper.get('sidebar_diff_mode', 'dual')
  if not VALID_MODES[mode] then mode = 'dual' end
  return mode
end

function M.set_mode(mode)
  if not VALID_MODES[mode] then return end
  env_keeper.set('sidebar_diff_mode', mode)
end

function M.toggle_mode()
  local next_mode = M.get_mode() == 'dual' and 'single' or 'dual'
  M.set_mode(next_mode)
  return next_mode
end

function M.show(item, on_state_change)
  local node = item.node
  local targets = M.resolve_diff_targets(item)
  local max_bytes = config.diff_max_bytes
  local cwd = vim.fn.getcwd()
  -- Capture this tab's state so the async callbacks always write back
  -- into the originating tab even if the user switches tabs mid-fetch.
  local ts = state.tab()

  local pending = 2
  local left_data, right_data, head_short
  local rendered = false
  local timeout_timer

  local function render_dual(d, changes_only, left_title)
    local gap = 2
    local total_width = math.floor(vim.o.columns * 0.85)
    local half_width = math.floor((total_width - gap) / 2)
    local height = math.floor(vim.o.lines * 0.8)
    local row = math.floor((vim.o.lines - height) / 2)
    local col_left = math.floor((vim.o.columns - total_width) / 2)
    local col_right = col_left + half_width + gap

    local ft = vim.filetype.match({ filename = node.abs_path }) or ''

    local function make_buf(data)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].buftype = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      if ft ~= '' and data.kind == 'text' then
        vim.bo[buf].filetype = ft
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, data.lines)
      vim.bo[buf].modifiable = false
      return buf
    end

    d.buf_left = make_buf(left_data)
    d.buf_right = make_buf(right_data)

    d.win_left = vim.api.nvim_open_win(d.buf_left, false, {
      relative = 'editor',
      row = row, col = col_left,
      width = half_width, height = height,
      style = 'minimal', border = 'rounded',
      title = left_title, title_pos = 'center',
    })
    vim.wo[d.win_left].diff = true
    vim.wo[d.win_left].scrollbind = true
    vim.wo[d.win_left].wrap = false
    vim.wo[d.win_left].foldmethod = 'diff'
    vim.wo[d.win_left].foldlevel = changes_only and 0 or 99
    vim.wo[d.win_left].foldenable = changes_only
    vim.wo[d.win_left].cursorline = false

    d.win_right = vim.api.nvim_open_win(d.buf_right, false, {
      relative = 'editor',
      row = row, col = col_right,
      width = half_width, height = height,
      style = 'minimal', border = 'rounded',
      title = targets.right_title, title_pos = 'center',
    })
    vim.wo[d.win_right].diff = true
    vim.wo[d.win_right].scrollbind = true
    vim.wo[d.win_right].wrap = false
    vim.wo[d.win_right].foldmethod = 'diff'
    vim.wo[d.win_right].foldlevel = changes_only and 0 or 99
    vim.wo[d.win_right].foldenable = changes_only
    vim.wo[d.win_right].cursorline = false

    local function close_and_return()
      vim.schedule(function()
        close_for(ts)
        if on_state_change then on_state_change(nil) end
        if ts.win and vim.api.nvim_win_is_valid(ts.win) then
          vim.api.nvim_set_current_win(ts.win)
        end
      end)
    end

    local function toggle_changes_only()
      changes_only = not changes_only
      env_keeper.set('sidebar_diff_changes_only', changes_only)
      for _, w in ipairs({ d.win_left, d.win_right }) do
        if w and vim.api.nvim_win_is_valid(w) then
          vim.wo[w].foldenable = changes_only
          vim.wo[w].foldlevel = changes_only and 0 or 99
        end
      end
      vim.notify('Changes only: ' .. (changes_only and 'on' or 'off'), vim.log.levels.INFO)
    end

    local function toggle_mode_here()
      M.set_mode('single')
      vim.notify('Diff mode: single', vim.log.levels.INFO)
      vim.schedule(function() M.show(item, on_state_change) end)
    end

    for _, buf in ipairs({ d.buf_left, d.buf_right }) do
      local bopts = { buffer = buf, nowait = true, silent = true }
      vim.keymap.set('n', 'q', close_and_return, bopts)
      vim.keymap.set('n', 'd', toggle_changes_only, bopts)
      vim.keymap.set('n', 'gd', toggle_mode_here, bopts)
    end

    vim.keymap.set('n', '<c-l>', function()
      if d.win_right and vim.api.nvim_win_is_valid(d.win_right) then
        vim.api.nvim_set_current_win(d.win_right)
      end
    end, { buffer = d.buf_left, nowait = true, silent = true })
    vim.keymap.set('n', '<c-h>', function()
      if d.win_left and vim.api.nvim_win_is_valid(d.win_left) then
        vim.api.nvim_set_current_win(d.win_left)
      end
    end, { buffer = d.buf_right, nowait = true, silent = true })

    local cur_left, cur_right = d.win_left, d.win_right
    for _, win_id in ipairs({ cur_left, cur_right }) do
      vim.api.nvim_create_autocmd('WinClosed', {
        pattern = tostring(win_id),
        once = true,
        callback = function()
          if on_state_change then on_state_change(nil) end
          vim.schedule(function()
            local cur = dp(ts)
            if cur.win_left ~= cur_left or cur.win_right ~= cur_right then
              return
            end
            close_for(ts)
            if ts.win and vim.api.nvim_win_is_valid(ts.win) then
              vim.api.nvim_set_current_win(ts.win)
            end
          end)
        end,
      })
    end
  end

  local function build_unified_diff_lines(left_lines, right_lines, left_title, right_title)
    local left_text = #left_lines > 0 and (table.concat(left_lines, '\n') .. '\n') or ''
    local right_text = #right_lines > 0 and (table.concat(right_lines, '\n') .. '\n') or ''
    local ok, diff_str = pcall(vim.text.diff, left_text, right_text, {
      algorithm = 'histogram',
      ctxlen = 3,
    })
    if not ok or not diff_str or diff_str == '' then
      return { '--- a' .. left_title, '+++ b' .. right_title, '', '-- No changes --' }
    end
    local lines = vim.split(diff_str, '\n', { plain = true })
    if #lines > 0 and lines[#lines] == '' then table.remove(lines) end
    table.insert(lines, 1, '+++ b' .. right_title)
    table.insert(lines, 1, '--- a' .. left_title)
    return lines
  end

  local function render_single(d, left_title)
    local width = math.floor(vim.o.columns * 0.85)
    local height = math.floor(vim.o.lines * 0.8)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local lines = build_unified_diff_lines(left_data.lines, right_data.lines, left_title, targets.right_title)

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'diff'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    d.buf_single = buf
    d.win_single = vim.api.nvim_open_win(buf, false, {
      relative = 'editor',
      row = row, col = col,
      width = width, height = height,
      style = 'minimal', border = 'single',
      title = left_title .. '  →' .. targets.right_title,
      title_pos = 'center',
    })
    vim.wo[d.win_single].wrap = false
    vim.wo[d.win_single].cursorline = false
    vim.wo[d.win_single].number = false
    vim.wo[d.win_single].relativenumber = false
    vim.wo[d.win_single].signcolumn = 'no'
    vim.wo[d.win_single].foldcolumn = '0'
    vim.wo[d.win_single].winhighlight = 'Normal:Normal,FloatBorder:Fg'

    local function close_and_return()
      vim.schedule(function()
        close_for(ts)
        if on_state_change then on_state_change(nil) end
        if ts.win and vim.api.nvim_win_is_valid(ts.win) then
          vim.api.nvim_set_current_win(ts.win)
        end
      end)
    end

    local function toggle_mode_here()
      M.set_mode('dual')
      vim.notify('Diff mode: dual', vim.log.levels.INFO)
      vim.schedule(function() M.show(item, on_state_change) end)
    end

    local bopts = { buffer = buf, nowait = true, silent = true }
    vim.keymap.set('n', 'q', close_and_return, bopts)
    vim.keymap.set('n', 'gd', toggle_mode_here, bopts)

    local cur_win = d.win_single
    vim.api.nvim_create_autocmd('WinClosed', {
      pattern = tostring(cur_win),
      once = true,
      callback = function()
        if on_state_change then on_state_change(nil) end
        vim.schedule(function()
          local cur = dp(ts)
          if cur.win_single ~= cur_win then return end
          close_for(ts)
          if ts.win and vim.api.nvim_win_is_valid(ts.win) then
            vim.api.nvim_set_current_win(ts.win)
          end
        end)
      end,
    })
  end

  local function maybe_render()
    if pending > 0 or rendered then return end
    if timeout_timer then
      pcall(function() timeout_timer:stop() end)
      pcall(function() timeout_timer:close() end)
      timeout_timer = nil
    end
    rendered = true
    local d = dp(ts)
    close_for(ts)
    ui.close_current_popup()
    if on_state_change then on_state_change('diff') end

    -- If a fetch never delivered (e.g. timeout fired), substitute a
    -- placeholder so the diff still opens instead of hanging.
    left_data = left_data or { lines = { '[fetch timed out]' }, kind = 'missing' }
    right_data = right_data or { lines = { '[fetch timed out]' }, kind = 'missing' }

    local changes_only = env_keeper.get('sidebar_diff_changes_only', false)

    -- Augment HEAD title with short hash when appropriate.
    local left_title = targets.left_title
    if left_title:find('HEAD') and head_short and head_short ~= '' then
      left_title = left_title:gsub('HEAD', 'HEAD (' .. head_short .. ')')
    end

    if M.get_mode() == 'single' then
      render_single(d, left_title)
    else
      render_dual(d, changes_only, left_title)
    end
  end

  -- Worktree-binary fast path: if both sides would resolve to a binary file,
  -- skip the diff and fall back to plain preview.
  if targets.right.kind == 'worktree' and vim.fn.filereadable(node.abs_path) == 1 then
    local fd = vim.uv.fs_open(node.abs_path, 'r', 438)
    if fd then
      local probe = vim.uv.fs_read(fd, 8192, 0)
      vim.uv.fs_close(fd)
      if bytes_look_binary(probe) then
        close_for(ts)
        if on_state_change then on_state_change('file') end
        ui.preview(node.abs_path)
        return
      end
    end
  end

  -- Fallback: if any vim.system callback is lost, render after 5s with
  -- the data we have so the diff floats never hang.
  timeout_timer = vim.uv.new_timer()
  if timeout_timer then
    timeout_timer:start(5000, 0, vim.schedule_wrap(function()
      pcall(function() timeout_timer:close() end)
      timeout_timer = nil
      if rendered then return end
      pending = 0
      maybe_render()
    end))
  end

  fetch_source(targets.left, max_bytes, function(data)
    left_data = data
    pending = pending - 1
    maybe_render()
  end)
  fetch_source(targets.right, max_bytes, function(data)
    right_data = data
    pending = pending - 1
    maybe_render()
  end)

  if targets.left_title:find('HEAD') then
    pending = pending + 1
    get_short_head(cwd, function(hash)
      head_short = hash
      pending = pending - 1
      maybe_render()
    end)
  end
end

return M
