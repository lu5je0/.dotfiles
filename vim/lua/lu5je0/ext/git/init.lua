local line_log = require('lu5je0.ext.git.line-log')

local M = {}

function M.setup()
  vim.keymap.set('x', '<leader>gl', line_log.show, { desc = 'Git line log' })
  vim.keymap.set('n', '<leader>gL', function()
    line_log.show({ start_line = 1, end_line = vim.api.nvim_buf_line_count(0) })
  end, { desc = 'Git file log' })
end

return M
