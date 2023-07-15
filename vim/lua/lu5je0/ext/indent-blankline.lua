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

local group = vim.api.nvim_create_augroup('IndentBlankLineFix', { clear = true })
vim.api.nvim_create_autocmd('User', {
  group = group,
  pattern = 'FoldChanged',
  callback = function()
    vim.cmd('IndentBlanklineRefresh')
  end,
})

vim.api.nvim_create_autocmd('WinScrolled', {
  group = group,
  callback = function()
    if vim.v.event.all.leftcol ~= 0 then
      vim.cmd('silent! IndentBlanklineRefresh')
    end
  end,
})
