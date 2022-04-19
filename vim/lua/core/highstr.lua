local high_str = require("high-str")
high_str.setup {
  verbosity = 0,
  saving_path = "/tmp/highstr/",
  highlight_colors = {
    -- color_id = {"bg_hex_code",<"fg_hex_code"/"smart">}
    color_1 = { "#ECBE7B", "smart" }, -- Pastel yellow
    color_2 = { "#ec5f67", "smart" }, -- Orange red
    color_3 = { "#98be65", "smart" }, -- Office green
    color_4 = { "#7d5c34", "smart" }, -- Fallow brown
    color_5 = { "#cccccc", "smart" },
    color_6 = { "#008080", "smart" },
    color_7 = { "#FF8800", "smart" },
    color_8 = { "#a9a1e1", "smart" },
    color_9 = { "#c678dd", "smart" },
    color_10 = { "#51afef", "smart" },
  }
}

local opts = { noremap = true, silent = true }
vim.api.nvim_set_keymap("v", "<F1>", ":<c-u>HSHighlight 1<CR>", opts)
vim.api.nvim_set_keymap("v", "<F2>", ":<c-u>HSHighlight 2<CR>", opts)
vim.api.nvim_set_keymap("v", "<F3>", ":<c-u>HSHighlight 3<CR>", opts)
vim.api.nvim_set_keymap("v", "<F4>", ":<c-u>HSHighlight 4<CR>", opts)
vim.api.nvim_set_keymap("v", "<F5>", ":<c-u>HSRmHighlight<CR>", opts)

-- vim.keymap.set('v', '<F6>', function()
--   -- vim.cmd("normal v<c-u>")
--   vim.cmd('HSHighlight 4')
--   require("high-str.main").main('highlight', math.random(1, 10))
--   -- vim.api.nvim_set_keymap("v", "<F5>", ":<c-u>HSRmHighlight<CR>", opts)
-- end, opts)
