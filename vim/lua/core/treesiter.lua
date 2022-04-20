require('nvim-treesitter.configs').setup {
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
}

local define_modules = require('nvim-treesitter').define_modules
local query = require('nvim-treesitter.query')

local foldmethod_backups = {}
local foldexpr_backups = {}

local fold_skip_filetypes = { 'markdown' }

define_modules {
  folding = {
    enable = true,
    attach = function(bufnr)
      if table.contain(fold_skip_filetypes, vim.bo.filetype) then
        return
      end
      -- Fold settings are actually window based...
      foldmethod_backups[bufnr] = vim.wo.foldmethod
      foldexpr_backups[bufnr] = vim.wo.foldexpr
      vim.wo.foldmethod = 'expr'
      vim.wo.foldexpr = 'nvim_treesitter#foldexpr()'
      vim.cmd([[
      nmap <buffer> <silent> zc :lua _G.fold_patch()<cr>
      vmap <buffer> <silent> v <esc>m':lua require'nvim-treesitter.incremental_selection'.node_incremental()<CR>
      vmap <buffer> <silent> V <esc>:lua require'nvim-treesitter.incremental_selection'.node_decremental()<CR>
      ]])
    end,
    detach = function(bufnr)
      if foldmethod_backups[bufnr] == nil then
        foldmethod_backups[bufnr] = 'manual'
        foldexpr_backups[bufnr] = ''
      end
      vim.wo.foldmethod = foldmethod_backups[bufnr]
      vim.wo.foldexpr = foldexpr_backups[bufnr]
      foldmethod_backups[bufnr] = nil
      foldexpr_backups[bufnr] = nil

      vim.cmd([[
      silent! unmap zc 
      silent! unmap v
      silent! unmap V
      nnoremap v m'v
      nnoremap V m'V
      ]])
    end,
    is_supported = query.has_folds,
  },
}

vim.cmd([[
hi TSPunctBracket guifg=#ABB2BF

" hi! TSTitle ctermfg=168 guifg=#e06c75
" hi! link TSURI markdownUrl
" hi! link TSStrong markdownBold
]])

-- local parsers = require('nvim-treesitter.parsers').available_parsers()
-- table.remove_by_value(parsers, 'markdown')
-- vim.cmd(([[
--
-- augroup ts_fold_fix
--     autocmd!
--     autocmd Filetype %s setlocal foldmethod=expr | setlocal foldexpr=nvim_treesitter#foldexpr()
-- augroup END
-- ]]):format(table.concat(parsers, ',')))
