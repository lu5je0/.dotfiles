let g:Lf_StlSeparator = { 'left': '', 'right': '' }
let g:Lf_WindowPosition = 'popup'
let g:Lf_ShortcutF = "<leader>ff"
let g:Lf_CommandMap = {'<C-J>': ['<DOWN>'], '<C-K>': ['<UP>']}
let g:Lf_ShortcutB = ""
let g:Lf_PreviewInPopup = 1

let g:Lf_WildIgnore = {
            \ 'dir': ['.svn','.git','.hg'],
            \ 'file': ['*.sw?','~$*','*.bak','*.exe','*.o','*.so','*.py[co]']
            \}

let g:Lf_PopupHeight = 0.7

" let g:Lf_UseCache = 0      
" let g:Lf_UseMemoryCache = 0
" let g:Lf_PopupColorscheme = 'default'
" let g:Lf_RememberLastSearch = 1
silent! unmap <leader>f
