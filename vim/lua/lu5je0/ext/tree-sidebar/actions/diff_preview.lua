local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')
local ui = require('lu5je0.core.ui')
local env_keeper = require('lu5je0.misc.env-keeper')

local M = {}

M.win_left = nil
M.win_right = nil

local _buf_left = nil
local _buf_right = nil

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

function M.close()
  if M.win_left and vim.api.nvim_win_is_valid(M.win_left) then
    vim.api.nvim_win_close(M.win_left, true)
  end
  if M.win_right and vim.api.nvim_win_is_valid(M.win_right) then
    vim.api.nvim_win_close(M.win_right, true)
  end
  M.win_left = nil
  M.win_right = nil
  _buf_left = nil
  _buf_right = nil
end

function M.show(item, on_state_change)
  local node = item.node
  local targets = M.resolve_diff_targets(item)
  local max_bytes = config.diff_max_bytes
  local cwd = vim.fn.getcwd()

  local pending = 2
  local left_data, right_data, head_short

  local function maybe_render()
    if pending > 0 then return end
    M.close()
    ui.close_current_popup()
    if on_state_change then on_state_change('diff') end

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

    _buf_left = make_buf(left_data)
    _buf_right = make_buf(right_data)

    local changes_only = env_keeper.get('sidebar_diff_changes_only', false)

    -- Augment HEAD title with short hash when appropriate.
    local left_title = targets.left_title
    if left_title:find('HEAD') and head_short and head_short ~= '' then
      left_title = left_title:gsub('HEAD', 'HEAD (' .. head_short .. ')')
    end

    M.win_left = vim.api.nvim_open_win(_buf_left, false, {
      relative = 'editor',
      row = row, col = col_left,
      width = half_width, height = height,
      style = 'minimal', border = 'rounded',
      title = left_title, title_pos = 'center',
    })
    vim.wo[M.win_left].diff = true
    vim.wo[M.win_left].scrollbind = true
    vim.wo[M.win_left].wrap = false
    vim.wo[M.win_left].foldmethod = 'diff'
    vim.wo[M.win_left].foldlevel = changes_only and 0 or 99
    vim.wo[M.win_left].foldenable = changes_only
    vim.wo[M.win_left].cursorline = false

    M.win_right = vim.api.nvim_open_win(_buf_right, false, {
      relative = 'editor',
      row = row, col = col_right,
      width = half_width, height = height,
      style = 'minimal', border = 'rounded',
      title = targets.right_title, title_pos = 'center',
    })
    vim.wo[M.win_right].diff = true
    vim.wo[M.win_right].scrollbind = true
    vim.wo[M.win_right].wrap = false
    vim.wo[M.win_right].foldmethod = 'diff'
    vim.wo[M.win_right].foldlevel = changes_only and 0 or 99
    vim.wo[M.win_right].foldenable = changes_only
    vim.wo[M.win_right].cursorline = false

    local function close_and_return()
      vim.schedule(function()
        M.close()
        if on_state_change then on_state_change(nil) end
        if state.win and vim.api.nvim_win_is_valid(state.win) then
          vim.api.nvim_set_current_win(state.win)
        end
      end)
    end

    local function toggle_changes_only()
      changes_only = not changes_only
      env_keeper.set('sidebar_diff_changes_only', changes_only)
      for _, w in ipairs({ M.win_left, M.win_right }) do
        if w and vim.api.nvim_win_is_valid(w) then
          vim.wo[w].foldenable = changes_only
          vim.wo[w].foldlevel = changes_only and 0 or 99
        end
      end
      vim.notify('Changes only: ' .. (changes_only and 'on' or 'off'), vim.log.levels.INFO)
    end

    for _, buf in ipairs({ _buf_left, _buf_right }) do
      local bopts = { buffer = buf, nowait = true, silent = true }
      vim.keymap.set('n', 'q', close_and_return, bopts)
      vim.keymap.set('n', 'd', toggle_changes_only, bopts)
    end

    vim.keymap.set('n', '<c-l>', function()
      if M.win_right and vim.api.nvim_win_is_valid(M.win_right) then
        vim.api.nvim_set_current_win(M.win_right)
      end
    end, { buffer = _buf_left, nowait = true, silent = true })
    vim.keymap.set('n', '<c-h>', function()
      if M.win_left and vim.api.nvim_win_is_valid(M.win_left) then
        vim.api.nvim_set_current_win(M.win_left)
      end
    end, { buffer = _buf_right, nowait = true, silent = true })

    local cur_left, cur_right = M.win_left, M.win_right
    for _, win_id in ipairs({ cur_left, cur_right }) do
      vim.api.nvim_create_autocmd('WinClosed', {
        pattern = tostring(win_id),
        once = true,
        callback = function()
          if on_state_change then on_state_change(nil) end
          vim.schedule(function()
            if M.win_left ~= cur_left and M.win_right ~= cur_right then
              return
            end
            M.close()
            if state.win and vim.api.nvim_win_is_valid(state.win) then
              vim.api.nvim_set_current_win(state.win)
            end
          end)
        end,
      })
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
        M.close()
        if on_state_change then on_state_change('file') end
        ui.preview(node.abs_path)
        return
      end
    end
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
