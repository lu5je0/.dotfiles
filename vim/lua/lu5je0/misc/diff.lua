local M = {}

local ignore_fts = { 'NvimTree' }

function M.toggle_diff()
  local wins = vim.api.nvim_list_wins()
  for _, win_num in ipairs(wins) do
    local buffer_ft = vim.api.nvim_buf_get_option(vim.api.nvim_win_get_buf(win_num), 'ft')
    if not vim.tbl_contains(ignore_fts, buffer_ft) then
      -- todo
      vim.cmd('')
    end
  end
end

return M
