local M = {}

function M.setup()
  vim.g.Lf_StlSeparator = {
    left = '',
    right = ''
  }

  vim.g.Lf_WindowPosition = 'popup'

  vim.g.Lf_CommandMap = {
    ['<C-J>'] = {'<DOWN>'},
    ['<C-K>'] = {'<UP>'}
  }

  vim.g.Lf_ShortcutF = "<leader>ff"
  vim.g.Lf_ShortcutB = ""
  vim.g.Lf_PreviewInPopup = 1
  vim.g.Lf_PopupHeight = 0.7
  vim.g.Lf_PopupShowFoldcolumn = 0
  vim.g.Lf_WildIgnore = {
    dir = {'.svn','.git','.hg'},
    file = {'*.sw?','~$*','*.bak','*.exe','*.o','*.so','*.py[co]'}
  }

  vim.cmd('silent! unmap <leader>f')

  M.on_colorscheme()
end

function M.visual_leaderf(lf_cmd)
  local search = vim.call('visual#visual_selection')
  search = string.gsub(search, "'", "")
  search = string.gsub(search, "\n", "")

  vim.cmd(":Leaderf " .. lf_cmd .. " --input '" .. search .. "'")
end

function M.on_colorscheme()
  vim.cmd[[
  highlight Lf_hl_match cterm=bold ctermfg=107 gui=bold guifg=#a0c980
  highlight Lf_hl_match0 cterm=bold ctermfg=107 gui=bold guifg=#a0c980
  highlight Lf_hl_match1 cterm=bold ctermfg=110 gui=bold guifg=#6cb6eb
  highlight Lf_hl_match2 cterm=bold ctermfg=176 gui=bold guifg=#d38aea
  highlight Lf_hl_match3 cterm=bold ctermfg=203 gui=bold guifg=#ec7279
  highlight Lf_hl_match4 cterm=bold ctermfg=179 gui=bold guifg=#deb974
  highlight Lf_hl_matchRefine cterm=bold ctermfg=72 gui=bold guifg=#5dbbc1
  highlight Lf_hl_popup_normalMode cterm=bold ctermfg=235 ctermbg=107 gui=bold guifg=#2c2e34 guibg=#a0c980
  highlight Lf_hl_popup_inputMode cterm=bold ctermfg=235 ctermbg=110 gui=bold guifg=#2c2e34 guibg=#6cb6eb
  highlight Lf_hl_popup_category ctermfg=250 ctermbg=238 guifg=#c5cdd9 guibg=#414550
  highlight Lf_hl_popup_nameOnlyMode ctermfg=250 ctermbg=237 guifg=#c5cdd9 guibg=#3b3e48
  highlight Lf_hl_popup_fullPathMode ctermfg=250 ctermbg=237 guifg=#c5cdd9 guibg=#3b3e48
  highlight Lf_hl_popup_fuzzyMode ctermfg=250 ctermbg=237 guifg=#c5cdd9 guibg=#3b3e48
  highlight Lf_hl_popup_regexMode ctermfg=250 ctermbg=237 guifg=#c5cdd9 guibg=#3b3e48
  highlight Lf_hl_popup_lineInfo ctermfg=176 ctermbg=238 guifg=#d38aea guibg=#414550
  highlight Lf_hl_popup_total ctermfg=235 ctermbg=176 guifg=#2c2e34 guibg=#d38aea
  highlight Lf_hl_popup_cursor ctermfg=235 ctermbg=107 guifg=#2c2e34 guibg=#a0c980

  highlight! link Lf_hl_cursorline Ye
  highlight! link Lf_hl_selection DiffAdd
  highlight! link Lf_hl_rgHighlight Visual
  highlight! link Lf_hl_gtagsHighlight Visual
  highlight! link Lf_hl_popup_inputText Pmenu
  highlight! link Lf_hl_popup_window Pmenu
  highlight! link Lf_hl_popup_prompt Green
  highlight! link Lf_hl_popup_cwd Pmenu
  highlight! link Lf_hl_popup_blank Lf_hl_popup_window
  highlight! link Lf_hl_popup_spin Yellow
  ]]
end

return M
