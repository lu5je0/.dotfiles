local state = require('lu5je0.ext.sidebar.state')
local lifecycle = require('lu5je0.ext.sidebar.lifecycle')

local M = {}

local PREFIX = '[FILTER]: '

local function render_files(ctx)
  if lifecycle.is_current(ctx) then require('lu5je0.ext.sidebar.sources.files').render() end
end

function M.dispose(ctx)
  local files = ctx.state.files
  local s = files._live_filter
  if s.closing then return end
  s.closing = true
  local win, buf = s.win, s.buf
  s.win, s.buf = nil, nil
  if win and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
  if buf and vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
  if files.live_filter == '' then files.live_filter = nil end
  s.closing = false
end

local function remove_overlay(ctx)
  M.dispose(ctx)
  if not lifecycle.is_current(ctx) then return end
  render_files(ctx)
  vim.api.nvim_set_current_win(ctx.state.win)
end

local function get_filter_line_nr()
  local items = state.files.display_items or {}
  for i, item in ipairs(items) do
    if item.type == 'filter' then
      return i
    end
  end
  return nil
end

function M.start()
  if not state:is_open() then return end

  local ctx = lifecycle.capture()
  local ts = ctx.state
  remove_overlay(ctx)

  -- ensure filter state exists so header line renders
  if not state.files.live_filter then
    state.files.live_filter = ''
    render_files(ctx)
  end

  vim.api.nvim_set_current_win(state.win)

  local filter_line = get_filter_line_nr()
  if not filter_line then
    filter_line = 1
  end
  vim.api.nvim_win_set_cursor(state.win, { filter_line, #PREFIX - 1 })

  local s = ts.files._live_filter
  s.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[s.buf].buftype = 'nofile'
  vim.bo[s.buf].bufhidden = 'hide'

  local attached_buf = s.buf
  vim.api.nvim_buf_attach(s.buf, true, {
    on_lines = function()
      vim.schedule(function()
        if not attached_buf or not vim.api.nvim_buf_is_valid(attached_buf) then return end
        if not lifecycle.is_current(ctx) or s.buf ~= attached_buf then return end
        local lines = vim.api.nvim_buf_get_lines(attached_buf, 0, 1, false)
        local text = lines[1] or ''
        ts.files.live_filter = text
        render_files(ctx)
      end)
    end,
  })

  vim.api.nvim_buf_set_keymap(s.buf, 'i', '<CR>', '<cmd>stopinsert<CR>', { nowait = true })

  vim.api.nvim_create_autocmd('InsertLeave', {
    buffer = s.buf,
    once = true,
    callback = function()
      remove_overlay(ctx)
    end,
  })

  local win_info = vim.fn.getwininfo(state.win)[1]
  local win_width = win_info and (win_info.width - win_info.textoff - #PREFIX) or 20

  vim.schedule(function()
    if not lifecycle.is_current(ctx) then return end
    local cs = s
    if not cs.buf or not vim.api.nvim_buf_is_valid(cs.buf) then return end

    cs.win = vim.api.nvim_open_win(cs.buf, true, {
      relative = 'cursor',
      row = 0,
      col = 1,
      width = math.max(win_width, 1),
      height = 1,
      style = 'minimal',
      border = 'none',
      zindex = 50,
    })

    local prev = ts.files.live_filter or ''
    vim.api.nvim_buf_set_lines(cs.buf, 0, -1, false, { prev })
    vim.cmd('startinsert')
    vim.api.nvim_win_set_cursor(cs.win, { 1, #prev + 1 })
  end)
end

function M.clear()
  local ctx = lifecycle.capture()
  remove_overlay(ctx)
  ctx.state.files.live_filter = nil
  render_files(ctx)
end

return M
