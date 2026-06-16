local M = {}

local state = require('lu5je0.ext.winbar.state')

M.buffer_name_map = state.buffer_name_map

function M.refresh()
  require('lu5je0.ext.winbar.autocmds').refresh()
end

function M.setup()
  require('lu5je0.ext.winbar.highlights').apply()

  local group = vim.api.nvim_create_augroup('winbar', { clear = true })
  require('lu5je0.ext.winbar.autocmds').setup(group)

  vim.o.showtabline = 0

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buflisted then
    state.win_bufs[win] = { buf }
  end

  vim.wo[win].winbar = string.format(
    "%%{%%v:lua.require'lu5je0.ext.winbar.render'.winbar(%d)%%}", win
  )

  vim.schedule(function()
    require('lu5je0.ext.winbar.config').setup_keymaps()
    require('lu5je0.ext.winbar.commands').setup()
  end)
end

return M
