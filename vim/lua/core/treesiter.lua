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

vim.cmd(([[
set foldmethod=expr
set foldexpr=nvim_treesitter#foldexpr()
hi TSPunctBracket guifg=#ABB2BF

" hi! TSTitle ctermfg=168 guifg=#e06c75
" hi! link TSURI markdownUrl
" hi! link TSStrong markdownBold

augroup ts_fold_fix
    autocmd!
    autocmd Filetype %s set foldmethod=expr
augroup END
]]):format(table.concat(_G.ts_filtypes, ',')))
