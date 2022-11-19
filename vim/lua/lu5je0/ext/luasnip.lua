local M = {}

M.setup = function()
  local luasnip = require('luasnip')
  local opts = { silent = true }

  vim.keymap.set({ 's', 'i' }, '<c-j>', function() luasnip.jump(1) end, opts)
  vim.keymap.set({ 's', 'i' }, '<c-k>', function() luasnip.jump(-1) end, opts)
  
  require("luasnip.loaders.from_vscode").lazy_load({ paths = { "./snippets/" } })
end

return M
