local M = {}


-- mode
-- 'm'	Remap keys. This is default.  If {mode} is absent,
-- 	keys are remapped.
-- 'n'	Do not remap keys.
function M.feedkey(key, mode)
  if not mode then
    mode = 'm'
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, true, true), mode, true)
end

return M
