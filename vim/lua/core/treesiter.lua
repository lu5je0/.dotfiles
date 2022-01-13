require('nvim-treesitter.configs').setup({
  -- Modules and its options go here
  ensure_installed = _G.ts_filtypes,
  highlight = {
    enable = true,
  },
  incremental_selection = {
    enable = true,
  },
  textobjects = {
    enable = true,
  },
})

local fold_filetypes = vim.deepcopy(ts_filtypes)
table.remove_by_value(fold_filetypes, 'markdown')

vim.cmd(([[
hi TSPunctBracket guifg=#ABB2BF

" hi! TSTitle ctermfg=168 guifg=#e06c75
" hi! link TSURI markdownUrl
" hi! link TSStrong markdownBold

augroup ts_fold_fix
    autocmd!
    autocmd Filetype %s setlocal foldmethod=expr | setlocal foldexpr=nvim_treesitter#foldexpr()
augroup END
]]):format(table.concat(fold_filetypes, ',')))
