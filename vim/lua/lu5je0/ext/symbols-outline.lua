local M = {}

local function get_outline_width()
  local tab = vim.api.nvim_get_current_tabpage()
  local wins = vim.api.nvim_tabpage_list_wins(tab)
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "Outline" then
      return vim.api.nvim_win_get_width(win)
    end
  end
  return nil
end

local function keymap()
  vim.keymap.set('n', '<leader>i', function()
    if require('outline').is_open() then
      local width = get_outline_width()
      if width then
        require('outline.config').o.outline_window.width = width
      end
    end
    
    vim.cmd('Outline!')
  end)
  
  vim.keymap.set('n', '<leader>fi', function()
    vim.cmd('OutlineOpen')
    -- vim.cmd('norm zz')
  end)
end

function M.setup()
  require('outline').setup {
    outline_window = {
      center_on_jump = true,
    }
  }
  keymap()
end

return M
