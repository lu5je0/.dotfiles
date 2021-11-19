local M = {}

function M.lines_changes()
  local begin_line = vim.fn.getpos("'<")[2]
  local end_line = vim.fn.getpos("'>")[2]
  local filepath = vim.fn.expand("%:p")

  local cmd = string.format("Git log -L%s,%s:%s", begin_line, end_line, filepath)
  vim.cmd(cmd)
end

function M.current_file_logs()
  local filepath = vim.fn.expand("%:p")
  if filepath == "" then
    return
  end
  local cmd = string.format("Gclog -p %s", filepath)
  vim.cmd(cmd)
end

return M
