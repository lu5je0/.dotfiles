local M = {}

function M.selected_text()
  return vim.fn['visual#visual_selection']()
end

function M.visual_replace(text)
  vim.fn['VisualReplace'](text)
end

return M
