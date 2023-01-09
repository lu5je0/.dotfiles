local M = {}

local luasnip = require('luasnip')

local cmp = require('cmp')
local keys = require('lu5je0.core.keys')

-- 修复按下<c-j>后cmp补全位置不对的问题
local function cmp_hotfix()
  if cmp.visible() then
    cmp.close()
    keys.feedkey('<esc>a')
  end
end

M.jump_next_able = function()
  local modified_line = vim.fn.line("'^")
  local current_line = vim.fn.line(".")
  return modified_line >= current_line and modified_line - current_line <= 2 and luasnip.expand_or_locally_jumpable()
end

local function keymap()
  local opts = { silent = true }

  vim.keymap.set({ 's', 'i' }, '<c-j>', function()
    luasnip.jump(1)
    cmp_hotfix()
  end, opts)
  vim.keymap.set({ 's', 'i' }, '<c-k>', function()
    luasnip.jump(-1)
    cmp_hotfix()
  end, opts)

  for _, lhs in ipairs({ '<cr>', '<tab>' }) do
    vim.keymap.set({ 's', 'i' }, lhs, function()
      if luasnip.jumpable() then
        luasnip.jump(1)
        cmp_hotfix()
      end
    end, opts)
  end

  require("luasnip.loaders.from_vscode").lazy_load({ paths = { "./snippets/" } })
end

M.setup = function()
  keymap()
  require('lu5je0.ext.luasnips.snippets')
end


return M
