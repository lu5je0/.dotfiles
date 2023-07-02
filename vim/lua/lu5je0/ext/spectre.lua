local M = {}
local visul_util = require('lu5je0.core.visual')

local function keymap()
  vim.keymap.set('n', '<leader>xr', function()
    require("spectre").open_visual({ select_word = true })
  end, { desc = "Search current word" })

  vim.keymap.set('x', '<leader>xr', function()
    require("spectre").open({ search_text = visul_util.get_visual_selection_as_array()[1] })
  end, { desc = "Search current word" })

  vim.keymap.set('n', '<leader>xf', function()
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
