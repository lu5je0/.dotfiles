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
  }
}

vim.api.nvim_set_keymap("v", "<F1>", ":<c-u>HSHighlight 1<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<F2>", ":<c-u>HSHighlight 2<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<F3>", ":<c-u>HSHighlight 3<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<F4>", ":<c-u>HSHighlight 4<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<F5>", ":<c-u>HSRmHighlight<CR>", { noremap = true, silent = true })
