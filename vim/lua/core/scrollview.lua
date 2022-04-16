local M = {}

local scrollbar = require('scrollview')

M.begin_timer = function()
  local visible_duration = 3000

  local timer = nil
  local show = function()
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
  vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter', 'BufWinEnter', 'FocusGained', 'CursorMoved', 'VimResized' }, {
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
  scrollbar.setup {
    excluded_filetypes = { 'nerdtree' },
    current_only = true,
    -- winblend = 10,
    base = 'right',
    column = 1,
  }

  -- M.begin_timer()
end

return M
