local M = {}

function M.feedkey(key, mode)
  if not mode then
    mode = 'm'
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, true, true), mode, true)
end

return M
