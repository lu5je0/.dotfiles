local M = {}

function M.lines_changes(max_count)
    local begin_line = vim.fn.getpos('v')[2]
    local end_line = vim.api.nvim_win_get_cursor(0)[1]
    local filepath = vim.fn.expand('%:p')
    -- -max-count=50
    local cmd
    if max_count then
       cmd = string.format("Flogsplit -max-count=%s -raw-args=-L%s,%s:%s", max_count, begin_line, end_line, filepath)
     else
       cmd = string.format("Flogsplit -raw-args=-L%s,%s:%s", begin_line, end_line, filepath)
    end
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
  vim.keymap.set('n', '<leader>gL', M.current_file_logs, opts)
end

return M
