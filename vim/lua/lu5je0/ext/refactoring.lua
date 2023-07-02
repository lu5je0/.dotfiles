local M = {}


local function keymap()
  local map = vim.api.nvim_set_keymap
  -- Remaps for the refactoring operations currently offered by the plugin
  map("x", "<leader>cm", [[ <Esc><Cmd>lua require('refactoring').refactor('Extract Function')<CR>]],
    { noremap = true, silent = true, expr = false })
  map("x", "<leader>ci", [[ <Esc><Cmd>lua require('refactoring').refactor('Inline Variable')<CR>]],
    { noremap = true, silent = true, expr = false })
  map("x", "<leader>cv", [[ <Esc><Cmd>lua require('refactoring').refactor('Extract Variable')<CR>]],
    { noremap = true, silent = true, expr = false })
  map("n", "<leader>ci", [[ <Cmd>lua require('refactoring').refactor('Inline Variable')<CR>]],
    { noremap = true, silent = true, expr = false })
  map("n", "<leader>cm", [[ <Cmd>lua require('refactoring').refactor('Extract Block')<CR>]],
    { noremap = true, silent = true, expr = false })
  -- vim.api.nvim_set_keymap("v", "<leader>rf", [[ <Esc><Cmd>lua require('refactoring').refactor('Extract Function To File')<CR>]], {noremap = true, silent = true, expr = false})

  -- Extract block doesn't need visual mode
  -- vim.api.nvim_set_keymap("n", "<leader>rbf", [[ <Cmd>lua require('refactoring').refactor('Extract Block To File')<CR>]], {noremap = true, silent = true, expr = false})

  -- Inline variable can also pick up the identifier currently under the cursor without visual mode
end


function M.setup()
  require('refactoring').setup({})
  keymap()
end

return M
