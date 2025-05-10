local M = {}

function M.get_visual_selection_as_array()
  return vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type= vim.api.nvim_get_mode().mode })
end

function M.get_visual_selection_as_string()
  return table.concat(M.get_visual_selection_as_array(), '\n')
end

function M.visual_replace(text)
  -- Save the current 'a' register and its type
  local reg_tmp = vim.fn.getreg('a')
  local reg_type = vim.fn.getregtype('a')

  -- Set the 'a' register to the provided text
  vim.fn.setreg('a', text)

  -- Replace the selected text with the contents of 'a' register
  vim.api.nvim_command('normal! "ap')

  -- Restore the original 'a' register and its type
  vim.fn.setreg('a', reg_tmp, reg_type)
end

function M.visual_replace_by_fn(fn)
  M.visual_replace(fn(M.get_visual_selection_as_string()))
end

return M
