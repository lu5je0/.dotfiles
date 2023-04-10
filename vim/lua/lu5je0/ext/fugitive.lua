local M = {}

function M.lines_changes()
    local begin_line = vim.fn.getpos('v')[2]
    local end_line = vim.api.nvim_win_get_cursor(0)[1]
    local filepath = vim.fn.expand('%:p')
    local cmd = string.format("Flogsplit -max-count=500 -raw-args=-L%s,%s:%s", begin_line, end_line, filepath)
    vim.cmd(cmd)
end

function M.current_file_logs()
  local filepath = vim.fn.expand('%')
  if filepath ~= "" then
    vim.cmd('Flogsplit -path=' .. filepath)
  end
end

function M.setup()
  local opts = {}
  vim.keymap.set('x', '<leader>gl', M.lines_changes, opts)
  vim.keymap.set('l', '<leader>gL', M.current_file_logs, opts)
end

return M
