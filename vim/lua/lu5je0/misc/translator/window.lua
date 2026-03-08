local position = require('lu5je0.misc.translator.position')

local M = {}
local NS = vim.api.nvim_create_namespace('lu5je0_translator')

function M.has_float(state)
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

function M.clear_close_group(state)
  if state.close_group then
    pcall(vim.api.nvim_del_augroup_by_id, state.close_group)
    state.close_group = nil
  end
end

function M.close(state)
  M.clear_close_group(state)
  if M.has_float(state) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.source_win = nil
  state.request_id = state.request_id + 1
end

function M.focus(state)
  if not M.has_float(state) then
    return false
  end
  if vim.api.nvim_get_current_win() ~= state.win then
    vim.api.nvim_set_current_win(state.win)
  end
  return true
end

function M.set_anchor(state)
  state.source_win = vim.api.nvim_get_current_win()
end

local function ensure_window(state, lines, render_opts)
  local width_opts = vim.tbl_extend('force', state.opts or {}, render_opts or {})
  local width, height = position.calc_size(lines, width_opts)
  local config = position.make_config(width, height, {
    border = 'rounded',
    anchor_bias = 'auto',
    offset_x = 4,
    offset_y = 0,
  })

  if not M.has_float(state) or not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
    vim.api.nvim_set_option_value('filetype', 'translator', { buf = buf })
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
    vim.api.nvim_set_option_value('swapfile', false, { buf = buf })

    local win = vim.api.nvim_open_win(buf, false, config)
    vim.api.nvim_set_option_value('wrap', true, { win = win })
    vim.api.nvim_set_option_value('cursorline', true, { win = win })

    state.win = win
    state.buf = buf

    vim.keymap.set('n', 'q', function() M.close(state) end, { buffer = buf, silent = true })
    vim.keymap.set('n', '<esc>', function() M.close(state) end, { buffer = buf, silent = true })

    local group = vim.api.nvim_create_augroup('lu5je0_translator_close_' .. win, { clear = true })
    state.close_group = group

    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
      group = group,
      callback = function()
        if M.has_float(state) and vim.api.nvim_get_current_win() == state.source_win then
          M.close(state)
        end
      end,
    })

    vim.api.nvim_create_autocmd('WinClosed', {
      group = group,
      pattern = { tostring(win) },
      once = true,
      callback = function()
        if state.win == win then
          state.win = nil
          state.buf = nil
        end
        M.clear_close_group(state)
      end,
    })
  else
    vim.api.nvim_win_set_config(state.win, config)
  end
end

function M.render(state, lines, hls, opts)
  ensure_window(state, lines, opts)

  vim.api.nvim_set_option_value('modifiable', true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('readonly', true, { buf = state.buf })
  vim.api.nvim_set_option_value('modifiable', false, { buf = state.buf })

  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
  for _, item in ipairs(hls or {}) do
    vim.api.nvim_buf_add_highlight(state.buf, NS, item.hl, item.row, item.col_start, item.col_end)
  end
end

return M
