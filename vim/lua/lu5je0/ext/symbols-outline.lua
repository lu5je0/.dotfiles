local M = {}

local function keymap()
  vim.keymap.set('n', '<leader>d', function()
    vim.cmd('Outline!')
  end)
  
  -- vim.keymap.set('n', '<leader>fs', function()
  -- end)
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
