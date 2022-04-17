local M = {}

local scrollview = require('scrollview')

M.begin_timer = function()
  local visible_duration = 3000
  local timer = nil

  -- hack mouse handel
  local handle_mouse = scrollview.handle_mouse
  scrollview.handle_mouse = function(button)
    if timer then
      timer:stop()
      timer = nil
    end
    handle_mouse(button)
  end

  local show = function()
    -- local max_row = vim.fn.winheight(0)

    vim.cmd("ScrollViewEnable")

    if timer then
      timer:stop()
      timer = nil
    end
    timer = vim.defer_fn(function()
      vim.cmd("ScrollViewDisable")
    end, visible_duration)
  end

  local scroll_view_group = vim.api.nvim_create_augroup('scroll_view_group', { clear = true })
  -- vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter', 'BufWinEnter', 'FocusGained', 'CursorMoved', 'VimResized' }, {
  vim.api.nvim_create_autocmd({ 'WinScrolled' }, {
    group = scroll_view_group,
    pattern = { '*' },
    callback = show,
  })

  -- vim.api.nvim_create_autocmd({ 'WinLeave', 'BufLeave', 'BufWinLeave', 'FocusLost', 'QuitPre' }, {
  --   group = scroll_view_group,
  --   pattern = { '*' },
  --   callback = function()
  --     vim.cmd("ScrollViewDisable")
  --     -- scrollbar.clear()
  --   end,
  -- })
end

M.setup = function()
  scrollview.setup {
    excluded_filetypes = { 'nerdtree' , 'NvimTree'},
    current_only = false,
    winblend = 88,
    base = 'right',
    column = 1,
    on_startup = 1,
  }
  vim.cmd[[
  " Link ScrollView highlight to Pmenu highlight
  " highlight link ScrollView CursorLine

  " Specify custom highlighting for ScrollView
  highlight ScrollView guibg=LightCyan guifg=NONE
  ]]
  -- M.begin_timer()
end

return M
