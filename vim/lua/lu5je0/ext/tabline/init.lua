local M = {}

local state = require('lu5je0.ext.tabline.state')

M.buffer_name_map = state.buffer_name_map

function M.refresh()
  require('lu5je0.ext.tabline.autocmds').refresh()
end

function M.setup()
  require('lu5je0.ext.tabline.config').apply_highlights()

  local group = vim.api.nvim_create_augroup('tabline', { clear = true })
  require('lu5je0.ext.tabline.autocmds').setup(group)

  vim.o.showtabline = 0

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buflisted then
    state.win_bufs[win] = { buf }
  end

  vim.wo[win].winbar = string.format(
    "%%{%%v:lua.require'lu5je0.ext.tabline.render'.winbar(%d)%%}", win
  )

  vim.schedule(function()
    require('lu5je0.ext.tabline.keymaps').setup()
    require('lu5je0.ext.tabline.commands').setup()
  end)
end

return M
