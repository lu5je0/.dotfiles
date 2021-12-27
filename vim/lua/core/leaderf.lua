local M = {}

function M.setup()
  vim.g.Lf_StlSeparator = {
    left = '',
    right = '',
  }

  vim.g.Lf_WindowPosition = 'popup'

  vim.g.Lf_CommandMap = {
    ['<C-J>'] = { '<DOWN>' },
    ['<C-K>'] = { '<UP>' },
  }

  vim.g.Lf_ShortcutF = '<leader>ff'
  vim.g.Lf_ShortcutB = ''
  vim.g.Lf_PreviewInPopup = 1
  vim.g.Lf_PopupHeight = 0.7
  vim.g.Lf_PopupShowFoldcolumn = 0
  vim.g.Lf_WildIgnore = {
    dir = { '.svn', '.git', '.hg' },
    file = { '*.sw?', '~$*', '*.bak', '*.exe', '*.o', '*.so', '*.py[co]' },
  }

  vim.cmd('silent! unmap <leader>f')

  M.on_colorscheme()
  M.key_mappings()
end

function M.key_mappings()
  local opts = {}
  vim.api.nvim_set_keymap('n', '<leader>fC', ':Leaderf colorscheme<cr>', opts)
  vim.api.nvim_set_keymap('n', '<leader>ff', ':Leaderf file<cr>', opts)
  vim.api.nvim_set_keymap('n', '<leader>fs', ':Leaderf --recall<cr>', opts)
  vim.api.nvim_set_keymap('n', '<leader>fg', ':Leaderf bcommit<cr>', opts)
  vim.api.nvim_set_keymap('n', '<leader>fr', ':Leaderf rg<cr>', opts)
  vim.api.nvim_set_keymap('n', '<leader>fl', ':Leaderf line<cr>', opts)
  vim.api.nvim_set_keymap('n', '<leader>fn', ':Leaderf filetype<cr>', opts)
  vim.api.nvim_set_keymap('n', '<leader>fb', ':Leaderf buffer<cr>', opts)
  vim.api.nvim_set_keymap('n', '<leader>fm', ':Leaderf --nowrap mru<cr>', opts)
  vim.api.nvim_set_keymap('n', '<leader>fh', ':Leaderf help<cr>', opts)
  vim.api.nvim_set_keymap('n', '<leader>fj', ':JunkList<cr>', opts)
end

function M.visual_leaderf(lf_cmd)
  local search = vim.call('visual#visual_selection')
  search = string.gsub(search, "'", '')
  search = string.gsub(search, '\n', '')

  vim.cmd(':Leaderf ' .. lf_cmd .. " --input '" .. search .. "'")
end

function M.on_colorscheme()
  vim.cmd([[
  hi! Lf_hl_match cterm=bold ctermfg=107 gui=bold guifg=#a0c980
  hi! Lf_hl_match0 cterm=bold ctermfg=107 gui=bold guifg=#a0c980
  hi! Lf_hl_match1 cterm=bold ctermfg=110 gui=bold guifg=#6cb6eb
  hi! Lf_hl_match2 cterm=bold ctermfg=176 gui=bold guifg=#d38aea
  hi! Lf_hl_match3 cterm=bold ctermfg=203 gui=bold guifg=#ec7279
  hi! Lf_hl_match4 cterm=bold ctermfg=179 gui=bold guifg=#deb974
  hi! Lf_hl_matchRefine cterm=bold ctermfg=72 gui=bold guifg=#5dbbc1
  hi! Lf_hl_popup_normalMode cterm=bold ctermfg=235 ctermbg=107 gui=bold guifg=#2c2e34 guibg=#a0c980
  hi! Lf_hl_popup_inputMode cterm=bold ctermfg=235 ctermbg=110 gui=bold guifg=#2c2e34 guibg=#6cb6eb
  hi! Lf_hl_popup_category ctermfg=250 ctermbg=238 guifg=#c5cdd9 guibg=#414550
  hi! Lf_hl_popup_nameOnlyMode ctermfg=250 ctermbg=237 guifg=#c5cdd9 guibg=#3b3e48
  hi! Lf_hl_popup_fullPathMode ctermfg=250 ctermbg=237 guifg=#c5cdd9 guibg=#3b3e48
  hi! Lf_hl_popup_fuzzyMode ctermfg=250 ctermbg=237 guifg=#c5cdd9 guibg=#3b3e48
  hi! Lf_hl_popup_regexMode ctermfg=250 ctermbg=237 guifg=#c5cdd9 guibg=#3b3e48
  hi! Lf_hl_popup_lineInfo ctermfg=176 ctermbg=238 guifg=#d38aea guibg=#414550
  hi! Lf_hl_popup_total ctermfg=235 ctermbg=176 guifg=#2c2e34 guibg=#d38aea
  hi! Lf_hl_popup_cursor ctermfg=235 ctermbg=107 guifg=#2c2e34 guibg=#a0c980

  hi! link Lf_hl_cursorline Ye
  hi! link Lf_hl_selection DiffAdd
  hi! link Lf_hl_rgHi Visual
  hi! link Lf_hl_gtagsHi Visual
  hi! link Lf_hl_popup_inputText Pmenu
  hi! link Lf_hl_popup_window Pmenu
  hi! link Lf_hl_popup_prompt Green
  hi! link Lf_hl_popup_cwd Pmenu
  hi! link Lf_hl_popup_blank Lf_hl_popup_window
  hi! link Lf_hl_popup_spin Yellow
  ]])
end

return M
