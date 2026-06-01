local state = require('lu5je0.ext.tree-sidebar.state')
local ui = require('lu5je0.core.ui')
local env_keeper = require('lu5je0.misc.env-keeper')

local M = {}

M.win_left = nil
M.win_right = nil

local _buf_left = nil
local _buf_right = nil

local function is_binary_file(file_path)
  local fd = vim.uv.fs_open(file_path, 'r', 438)
  if not fd then return false end
  local data = vim.uv.fs_read(fd, 512, 0)
  vim.uv.fs_close(fd)
  if not data then return false end
  return data:find('\0') ~= nil
end

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
  local cwd = vim.fn.getcwd()
  local rel_path = node.abs_path:sub(#cwd + 2)
  local xy = node.xy or '  '

  if vim.fn.filereadable(node.abs_path) == 1 and is_binary_file(node.abs_path) then
    M.close()
    if on_state_change then on_state_change('file') end
    ui.preview(node.abs_path)
    return
  end

  local new_lines = {}
  if vim.fn.filereadable(node.abs_path) == 1 then
    new_lines = vim.fn.readfile(node.abs_path)
  end

  local function render_diff(old_lines)
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

    _buf_left = vim.api.nvim_create_buf(false, true)
    vim.bo[_buf_left].buftype = 'nofile'
    vim.bo[_buf_left].bufhidden = 'wipe'
    if ft ~= '' then vim.bo[_buf_left].filetype = ft end
    vim.api.nvim_buf_set_lines(_buf_left, 0, -1, false, old_lines)
    vim.bo[_buf_left].modifiable = false

    _buf_right = vim.api.nvim_create_buf(false, true)
    vim.bo[_buf_right].buftype = 'nofile'
    vim.bo[_buf_right].bufhidden = 'wipe'
    if ft ~= '' then vim.bo[_buf_right].filetype = ft end
    vim.api.nvim_buf_set_lines(_buf_right, 0, -1, false, new_lines)
    vim.bo[_buf_right].modifiable = false

    local changes_only = env_keeper.get('sidebar_diff_changes_only', false)

    M.win_left = vim.api.nvim_open_win(_buf_left, false, {
      relative = 'editor',
      row = row,
      col = col_left,
      width = half_width,
      height = height,
      style = 'minimal',
      border = 'rounded',
      title = ' HEAD ',
      title_pos = 'center',
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
      row = row,
      col = col_right,
      width = half_width,
      height = height,
      style = 'minimal',
      border = 'rounded',
      title = ' Working Tree ',
      title_pos = 'center',
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

    local cur_left, cur_right = M.win_left, M.win_right
    for _, win_id in ipairs({ cur_left, cur_right }) do
      vim.api.nvim_create_autocmd('WinClosed', {
        pattern = tostring(win_id),
        once = true,
        callback = function()
          vim.schedule(function()
            if M.win_left ~= cur_left and M.win_right ~= cur_right then
              return
            end
            M.close()
            if on_state_change then on_state_change(nil) end
          end)
        end,
      })
    end
  end

  if xy == '??' then
    render_diff({})
  else
    vim.system({ 'git', 'show', 'HEAD:' .. rel_path }, { text = true, cwd = cwd }, function(result)
      vim.schedule(function()
        local old_lines = {}
        if result.code == 0 and result.stdout then
          old_lines = vim.split(result.stdout, '\n', { plain = true })
          if #old_lines > 0 and old_lines[#old_lines] == '' then
            table.remove(old_lines)
          end
        end
        render_diff(old_lines)
      end)
    end)
  end
end

return M
