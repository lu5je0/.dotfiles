local M = {}

local state = require('lu5je0.ext.bufferline.state')

M.buffer_name_map = state.buffer_name_map

function M.refresh()
  require('lu5je0.ext.bufferline.autocmds').refresh()
end

function M.setup()
  require('lu5je0.ext.bufferline.config').apply_highlights()

  local group = vim.api.nvim_create_augroup('bufferline', { clear = true })
  require('lu5je0.ext.bufferline.autocmds').setup(group)

  vim.o.showtabline = 2
  vim.o.tabline = '%!v:lua.require\'lu5je0.ext.bufferline.render\'.tabline()'

  vim.schedule(function()
    require('lu5je0.ext.bufferline.keymaps').setup()
    require('lu5je0.ext.bufferline.commands').setup()
  end)
end

return M
