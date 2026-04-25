local line_log = require('lu5je0.ext.git.line-log')
local project_log = require('lu5je0.ext.git.project-log')
local git_status = require('lu5je0.ext.git.git-status')

local M = {}

function M.setup()
  vim.keymap.set('x', '<leader>gl', line_log.show, { desc = 'Git line log' })
  vim.keymap.set('n', '<leader>gl', project_log.show, { desc = 'Git project log' })
  vim.keymap.set('n', '<leader>gL', function()
    line_log.show({ start_line = 1, end_line = vim.api.nvim_buf_line_count(0) })
  end, { desc = 'Git file log' })
  vim.keymap.set('n', '<leader>gs', git_status.show, { desc = 'Git status' })
end

return M
