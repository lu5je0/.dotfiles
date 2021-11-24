local M = {}

local function load_plugin()
  require('core/plugins_helper').load_plugin("vim-fugitive")
end

function M.lines_changes()
  load_plugin()

  local begin_line = vim.fn.getpos("'<")[2]
  local end_line = vim.fn.getpos("'>")[2]
  local filepath = vim.fn.expand("%:p")

  local cmd = string.format("Git log -L%s,%s:%s", begin_line, end_line, filepath)
  vim.cmd(cmd)
end

function M.current_file_logs()
  load_plugin()

  local filepath = vim.fn.expand("%:p")
  if filepath == "" then
    return
  end
  local cmd = string.format("Gclog -p %s", filepath)
  vim.cmd(cmd)
end

return M
