local M = {}

function M.get_visual_selection_as_array()
  return vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type= vim.api.nvim_get_mode().mode })
end

function M.get_visual_selection_as_string()
  return table.concat(M.get_visual_selection_as_array(), '\n')
end

function M.visual_replace(text)
  vim.fn['visual#replace'](text)
end

function M.visual_replace_by_fn(fn)
  M.visual_replace(fn(M.get_visual_selection_as_string()))
end

return M
