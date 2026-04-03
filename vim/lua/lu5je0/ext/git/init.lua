local line_log = require('lu5je0.ext.git.line-log')

local M = {}

function M.setup()
  vim.keymap.set('x', '<leader>gl', line_log.show, { desc = 'Git line log' })
end

return M
