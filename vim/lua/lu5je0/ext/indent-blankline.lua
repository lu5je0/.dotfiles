vim.g.indent_blankline_char = '▏'
vim.g.indentLine_fileTypeExclude = { 'undotree', 'vista', 'git', 'diff', 'translator', 'help', 'packer',
'lsp-installer', 'toggleterm', 'confirm' }
-- vim.g.indent_blankline_filetype = _G.indent_blankline_filetypes
vim.g.indent_blankline_show_first_indent_level = false
vim.g.indent_blankline_show_trailing_blankline_indent = false
vim.cmd([[highlight IndentBlanklineIndent guifg=#373C44 gui=nocombine]])
require('indent_blankline').setup {
  space_char_blankline = ' ',
  char_highlight_list = {
    'IndentBlanklineIndent',
  },
}
