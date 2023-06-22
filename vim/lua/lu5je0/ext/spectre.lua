local M = {}

local function keymap()
  vim.keymap.set('n', '<leader>sw', function()
    require("spectre").open_visual({ select_word = true })
  end, { desc = "Search current word" })

  vim.keymap.set('x', '<leader>sw', function()
    require("spectre").open_visual()
  end, { desc = "Search current word" })

  vim.keymap.set('n', '<leader>sf', function()
    require("spectre").open_file_search({ select_word = true })
  end, { desc = "Search on current file" })
end

function M.setup()
  require('spectre').setup({
    highlight = {
      ui = "String",
      search = "DiffChange",
      replace = "DiffDelete"
    },
    mapping = {
      ['send_to_qf'] = {
        map = "Q",
        cmd = "<cmd>lua require('spectre.actions').send_to_qf()<CR>",
        desc = "send all item to quickfix"
      },
    }
  })
  
  keymap()
end

return M
