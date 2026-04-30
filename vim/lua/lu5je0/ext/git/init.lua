local line_log = require('lu5je0.ext.git.line-log')
local project_log = require('lu5je0.ext.git.project-log')
local git_status = require('lu5je0.ext.git.git-status')
local config = require('lu5je0.ext.git.config')

local M = {}

function M.setup(opts)
  opts = opts or {}

  local scopes = { 'git_status', 'project_log', 'line_log' }
  for k, v in pairs(opts) do
    if not vim.tbl_contains(scopes, k) then
      config[k] = v
    end
  end
  for _, scope in ipairs(scopes) do
    if opts[scope] then
      config[scope] = vim.tbl_extend('force', config[scope] or {}, opts[scope])
    end
  end
  vim.keymap.set('x', '<leader>gl', line_log.show, { desc = 'Git line log' })
  vim.keymap.set('n', '<leader>gl', project_log.show, { desc = 'Git project log' })
  vim.keymap.set('n', '<leader>gL', function()
    line_log.show({ start_line = 1, end_line = vim.api.nvim_buf_line_count(0) })
  end, { desc = 'Git file log' })
  vim.keymap.set('n', '<leader>gs', git_status.show, { desc = 'Git status' })
end

return M
