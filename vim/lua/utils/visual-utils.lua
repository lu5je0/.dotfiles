local M = {}

function M.selected_text()
  return vim.fn['visual#visual_selection']()
end

function M.replace_with(text)
  local cmd = [[
  function! TempString(s)
    return '%s'
  endfunction
  ]]
  cmd = cmd:format(text)
  vim.cmd(cmd)
  vim.fn['ReplaceSelect']('TempString')
end

return M
