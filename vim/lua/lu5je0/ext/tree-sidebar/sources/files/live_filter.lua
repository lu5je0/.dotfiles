local state = require('lu5je0.ext.tree-sidebar.state')

local M = {}

local PREFIX = '[FILTER]: '

local function lf()
  return state.files._live_filter
end

local function render_files()
  local files = require('lu5je0.ext.tree-sidebar.sources.files')
  files.render()
end

local function remove_overlay()
  local s = lf()
  if s.closing then return end
  s.closing = true

  local ok, err = pcall(function()
    if s.win and vim.api.nvim_win_is_valid(s.win) then
      vim.api.nvim_win_close(s.win, true)
    end
    if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
      vim.api.nvim_buf_delete(s.buf, { force = true })
    end
    s.win = nil
    s.buf = nil

    if not state.files.live_filter or state.files.live_filter == '' then
      state.files.live_filter = nil
      render_files()
    end

    if state:is_open() then
      vim.api.nvim_set_current_win(state.win)
    end
  end)

  s.closing = false
  if not ok then error(err) end
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

  remove_overlay()

  -- ensure filter state exists so header line renders
  if not state.files.live_filter then
    state.files.live_filter = ''
    render_files()
  end

  vim.api.nvim_set_current_win(state.win)

  local filter_line = get_filter_line_nr()
  if not filter_line then
    filter_line = 1
  end
  vim.api.nvim_win_set_cursor(state.win, { filter_line, #PREFIX - 1 })

  local s = lf()
  s.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[s.buf].buftype = 'nofile'
  vim.bo[s.buf].bufhidden = 'hide'

  local attached_buf = s.buf
  vim.api.nvim_buf_attach(s.buf, true, {
    on_lines = function()
      vim.schedule(function()
        if not attached_buf or not vim.api.nvim_buf_is_valid(attached_buf) then return end
        if lf().buf ~= attached_buf then return end
        local lines = vim.api.nvim_buf_get_lines(attached_buf, 0, 1, false)
        local text = lines[1] or ''
        state.files.live_filter = text
        render_files()
      end)
    end,
  })

  vim.api.nvim_buf_set_keymap(s.buf, 'i', '<CR>', '<cmd>stopinsert<CR>', { nowait = true })

  vim.api.nvim_create_autocmd('InsertLeave', {
    buffer = s.buf,
    once = true,
    callback = function()
      remove_overlay()
    end,
  })

  local win_info = vim.fn.getwininfo(state.win)[1]
  local win_width = win_info and (win_info.width - win_info.textoff - #PREFIX) or 20

  vim.schedule(function()
    if not state:is_open() then return end
    local cs = lf()
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

    local prev = state.files.live_filter or ''
    vim.api.nvim_buf_set_lines(cs.buf, 0, -1, false, { prev })
    vim.cmd('startinsert')
    vim.api.nvim_win_set_cursor(cs.win, { 1, #prev + 1 })
  end)
end

function M.clear()
  remove_overlay()
  state.files.live_filter = nil
  render_files()
end

return M
