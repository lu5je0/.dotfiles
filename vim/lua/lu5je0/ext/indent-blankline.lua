-- vim.g.indent_blankline_show_trailing_blankline_indent = false
local ibl = require('ibl')
local hooks = require "ibl.hooks"

local highlight = {
  "IndentBlankline",
}
vim.api.nvim_set_hl(0, "IndentBlankline", { fg = "#373C44" })

hooks.register(
  hooks.type.WHITESPACE,
  hooks.builtin.hide_first_space_indent_level
)

require "ibl".overwrite {
  exclude = {
    filetypes = { 'undotree', 'vista', 'git', 'diff', 'translator', 'help', 'packer',
      'lsp-installer', 'toggleterm', 'confirm' }
  }
}

ibl.setup {
  -- 大于100，<<时文本会闪烁
  debounce = 50,
  indent = {
    char = "▏",
    highlight = highlight,
  },
  whitespace = {
    remove_blankline_trail = false,
  },
  scope = { enabled = false, },
}

-- fix 文本闪烁
-- vim.keymap.set('n', '==', function()
--   vim.cmd('IBLDisable')
--   vim.cmd("norm! ==")
--   vim.cmd('IBLEnable')
-- end, { silent = true })
--
-- vim.keymap.set('x', '=', function()
--   vim.cmd('IBLDisable')
--   vim.cmd("norm! =")
--   vim.cmd('IBLEnable')
-- end, { silent = true })
--
-- local keys = require('lu5je0.core.keys')
-- vim.keymap.set('x', '>', function()
--   vim.cmd('IBLDisable')
--   keys.feedkey('>gv', 'n')
--   vim.schedule(function()
--     vim.cmd('IBLEnable')
--   end)
-- end, { silent = true })
--
-- vim.keymap.set('x', '<', function()
--   vim.cmd('IBLDisable')
--   keys.feedkey('<gv', 'n')
--   vim.schedule(function()
--     vim.cmd('IBLEnable')
--   end)
-- end, { silent = true })
--
-- vim.keymap.set('n', '<space>>', function()
--   vim.cmd('IBLDisable')
--   keys.feedkey('`[v`]>^', 'n')
--   vim.schedule(function()
--     vim.cmd('IBLEnable')
--   end)
-- end, { silent = true })
--
-- vim.keymap.set('n', '<space><', function()
--   vim.cmd('IBLDisable')
--   keys.feedkey('`[v`]<^', 'n')
--   vim.schedule(function()
--     vim.cmd('IBLEnable')
--   end)
-- end, { silent = true })
