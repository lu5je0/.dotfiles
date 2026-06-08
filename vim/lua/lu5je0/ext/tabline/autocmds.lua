local M = {}

local state = require('lu5je0.ext.tabline.state')

local function refresh()
  if state.refresh_scheduled then return end
  state.refresh_scheduled = true
  vim.schedule(function()
    state.refresh_scheduled = false
    pcall(vim.cmd.redrawtabline)
  end)
end

M.refresh = refresh

function M.setup(group)
  vim.api.nvim_create_autocmd({
    'BufAdd', 'BufDelete', 'BufWipeout',
    'BufEnter', 'BufWinEnter',
    'BufModifiedSet', 'BufWritePost',
    'WinResized', 'WinNew', 'WinClosed',
    'TabEnter',
  }, {
    group = group,
    callback = refresh,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      require('lu5je0.ext.tabline.config').apply_highlights()
      require('lu5je0.ext.tabline.render').clear_icon_hl_cache()
      refresh()
    end,
  })
end

return M
