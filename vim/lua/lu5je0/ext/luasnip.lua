local M = {}

local luasnip = require('luasnip')

M.jump_next_able = function()
  return luasnip.expand_or_jumpable() and (vim.fn.line("'^") - vim.fn.line('.')) <= 2
end

local function keymap()
  local opts = { silent = true }

  vim.keymap.set({ 's', 'i' }, '<c-j>', function() luasnip.jump(1) end, opts)
  vim.keymap.set({ 's', 'i' }, '<c-k>', function() luasnip.jump(-1) end, opts)
  vim.keymap.set({ 's' }, '<cr>', function()
    if luasnip.jumpable() then
      luasnip.jump(1)
    end
  end, opts)

  require("luasnip.loaders.from_vscode").lazy_load({ paths = { "./snippets/" } })
end

M.setup = function()
  keymap()
  -- require('lu5je0.ext.luasnips.snippets')
end


return M
