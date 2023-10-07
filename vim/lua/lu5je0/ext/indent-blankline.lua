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
  indent = {
    char = "▏",
    highlight = highlight,
  },
  whitespace = {
    remove_blankline_trail = false,
  },
  scope = { enabled = false, },
}
