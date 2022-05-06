local M = {}

function M.selected_text()
  return vim.fn['visual#visual_selection']()
end

function M.selected_text_by_yank()
  return vim.fn['visual#visual_selection_by_yank']()
end

function M.visual_replace(text)
  vim.fn['VisualReplace'](text)
end

return M
