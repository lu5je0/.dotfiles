local M = {}

local function keymap()
  vim.keymap.set('n', '<leader>i', function()
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
