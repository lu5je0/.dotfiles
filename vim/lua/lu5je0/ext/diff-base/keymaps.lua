local M = {}

function M.apply(bufnr)
  local actions = require('lu5je0.ext.diff-base.actions')
  local opts = { buffer = bufnr, silent = true }
  vim.keymap.set('n', '<leader>gg', actions.preview_hunk, opts)
  vim.keymap.set('n', ']g', actions.next_hunk, opts)
  vim.keymap.set('n', '[g', actions.prev_hunk, opts)
  vim.keymap.set('n', ']c', actions.next_hunk, opts)
  vim.keymap.set('n', '[c', actions.prev_hunk, opts)
  vim.keymap.set('n', '<leader>gd', actions.diffthis, opts)
  vim.keymap.set('n', '<leader>ga', actions.stage_hunk, opts)
  vim.keymap.set('n', '<leader>gA', actions.stage_buffer, opts)
  vim.keymap.set('n', '<leader>gr', actions.unstage_hunk, opts)
  vim.keymap.set('n', '<leader>gR', actions.unstage_buffer, opts)
  vim.keymap.set('n', '<leader>gu', actions.reset_hunk, opts)
  vim.keymap.set('n', '<leader>gC', actions.reset_buffer, opts)
  vim.keymap.set({ 'o', 'x' }, 'ig', actions.select_hunk, opts)
end

function M.clear(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  for _, lhs in ipairs({ '<leader>gg', ']g', '[g', ']c', '[c', '<leader>gd', '<leader>ga', '<leader>gA', '<leader>gr', '<leader>gR', '<leader>gu', '<leader>gC' }) do
    pcall(vim.keymap.del, 'n', lhs, { buffer = bufnr })
  end
  for _, mode in ipairs({ 'o', 'x' }) do
    pcall(vim.keymap.del, mode, 'ig', { buffer = bufnr })
  end
end

return M
