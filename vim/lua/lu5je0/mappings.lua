vim.g.mapleader = ','

vim.schedule(function()
  require('lu5je0.misc.var-naming-converter').key_mapping()
  require('lu5je0.misc.code-runner').key_mapping()
end)

-- option toggle
local option_toggler = require('lu5je0.misc.option-toggler')
local opts = { desc = 'mappings.lua', silent = true }

local function nmap_fn(rhs, fn)
  vim.keymap.set('n', rhs, fn, opts)
end

vim.defer_fn(function()
  -- movement
  vim.keymap.set({ 'x', 'n', 'o' }, 'H', '^', opts)
  vim.keymap.set({ 'x', 'n', 'o' }, 'L', '$', opts)

  -- quit
  vim.keymap.set({ 'n' }, '<leader>q', require("lu5je0.misc.quit-prompt").close_buffer, opts)
  vim.keymap.set({ 'n' }, '<leader>Q', require("lu5je0.misc.quit-prompt").exit, opts)

  -- toggle
  nmap_fn('<leader>vn', option_toggler.new_toggle_fn({ 'set nonumber', 'set number' }))
  nmap_fn('<leader>vp', option_toggler.new_toggle_fn({ 'set nopaste', 'set paste' }))
  nmap_fn('<leader>vm', option_toggler.new_toggle_fn({ 'set mouse=c', 'set mouse=a' }))
  nmap_fn('<leader>vs', option_toggler.new_toggle_fn({ 'set signcolumn=no', 'set signcolumn=yes:1' }))
  nmap_fn('<leader>vl', option_toggler.new_toggle_fn({ 'set cursorline', 'set nocursorline' }))
  nmap_fn('<leader>vf', option_toggler.new_toggle_fn({ 'set foldcolumn=auto:9', 'set foldcolumn=0' }))
  nmap_fn('<leader>vd', option_toggler.new_toggle_fn({ 'windo difft', 'windo diffo' }))
  nmap_fn('<leader>vh', option_toggler.new_toggle_fn({ 'call hexedit#ToggleHexEdit()' }))
  nmap_fn('<leader>vc', option_toggler.new_toggle_fn({ 'set noignorecase', 'set ignorecase' }))
  nmap_fn('<leader>vi', option_toggler.new_toggle_fn(function() vim.fn['ToggleSaveLastIme']() end))

  nmap_fn('<leader>vw', function()
    local buffer_opts = vim.deepcopy(opts)
    buffer_opts.buffer = true
    if vim.wo.wrap then
      vim.wo.wrap = false
      vim.keymap.del({ 'x', 'n' }, 'j', { buffer = 0 })
      vim.keymap.del({ 'x', 'n' }, 'k', { buffer = 0 })
      vim.keymap.del({ 'x', 'n', 'o' }, 'H', { buffer = 0 })
      vim.keymap.del({ 'x', 'n', 'o' }, 'L', { buffer = 0 })
      vim.keymap.del({ 'o' }, 'Y', { buffer = 0 })
    else
      vim.wo.wrap = true
      vim.keymap.set({ 'x', 'n' }, 'j', 'gj', buffer_opts)
      vim.keymap.set({ 'x', 'n' }, 'k', 'gk', buffer_opts)
      vim.keymap.set({ 'x', 'n', 'o' }, 'H', 'g^', buffer_opts)
      vim.keymap.set({ 'x', 'n', 'o' }, 'L', 'g$', buffer_opts)
      vim.keymap.set({ 'o' }, 'Y', 'gyg$', buffer_opts)
    end
  end)

  vim.cmd [[
  " ctrl-c 复制
  vnoremap <C-c> y

  " 缩进后重新选择
  xmap < <gv
  xmap > >gv

  imap <M-j> <down>
  imap <M-k> <up>
  imap <M-h> <left>
  imap <M-l> <right>

  map <silent> <m-cr> <leader>cc
  imap <silent> <m-cr> <leader>cc
  map <silent> <d-cr> <leader>cc
  imap <silent> <d-cr> <leader>cc

  " visual-multi
  map <c-d-n> <Plug>(VM-Add-Cursor-Down)
  map <c-d-p> <Plug>(VM-Add-Cursor-Up)
  map <c-m-n> <Plug>(VM-Add-Cursor-Down)
  map <c-m-p> <Plug>(VM-Add-Cursor-Up)

  nmap <F2> :bp<cr>
  nmap <F3> :bn<cr>
  nmap <PageUp>   :bprevious<CR>
  nmap <PageDown> :bnext<CR>

  "----------------------------------------------------------------------
  " <leader>
  "----------------------------------------------------------------------
  nmap <silent> <leader>tN :tabnew<cr>

  "----------------------------------------------------------------------
  " window control
  "----------------------------------------------------------------------
  " 快速切换窗口
  nmap <silent> <C-J> <C-w>j
  nmap <silent> <C-K> <C-w>k
  nmap <silent> <C-H> <C-w>h
  nmap <silent> <C-L> <C-w>l

  nmap <silent> <left> :bp<cr>
  nmap <silent> <right> :bn<cr>
  nmap <silent> <c-b>o <c-w>p
  nmap <silent> <c-b><c-o> <c-w>p
  nmap Q <cmd>execute 'normal @' .. reg_recorded()<CR>

  command! -nargs=1 SplitWithBuffer call SplitWithBuffer(<f-args>)

  " undotree esc映射
  function g:Undotree_CustomMap()
      nmap <buffer> <ESC> <plug>UndotreeClose
  endfunc

  " 打断undo
  inoremap . <c-g>u.

  "----------------------------------------------------------------------
  " text-objects
  "----------------------------------------------------------------------
  onoremap il :<c-u>normal! v$o^oh<cr>
  xnoremap il $o^oh

  onoremap ie :<c-u>normal! vgg0oG$<cr>
  xnoremap ie gg0oG$

  onoremap ae :<c-u>normal! vgg0oG$<cr>
  xnoremap ae gg0oG$

  "----------------------------------------------------------------------
  " visual mode
  "----------------------------------------------------------------------
  xmap <silent> # :lua require("ext.terminal").run_select_in_terminal()<cr>

  "----------------------------------------------------------------------
  " other
  "----------------------------------------------------------------------
  nnoremap * m`:keepjumps normal! *``<cr>
  xnoremap * m`:keepjumps <C-u>call visual#star_search_set('/')<CR>/<C-R>=@/<CR><CR>``
  nnoremap v m'v
  nnoremap V m'V

  "----------------------------------------------------------------------
  " leader
  "----------------------------------------------------------------------
  nmap <leader>% :%s/

  nmap <leader>wo <c-w>o

  " Echo translation in the cmdline
  nmap <silent> <Leader>sc <Plug>Translate
  xmap <silent> <Leader>sc <Plug>TranslateV

  " say it
  nmap <silent> <Leader>sa :call misc#say_it()<cr><Plug>TranslateW
  xmap <silent> <Leader>sa :call misc#visual_say_it()<cr><Plug>TranslateWV

  " xmap <silent> <Leader>sc <Plug>TranslateV
  " Display translation in a window
  nmap <silent> <Leader>ss <Plug>TranslateW
  xmap <silent> <Leader>ss <Plug>TranslateWV
  " Replace the text with translation
  nmap <silent> <Leader>sr <Plug>TranslateR
  xmap <silent> <Leader>sr <Plug>TranslateRV

  "----------------------------------------------------------------------
  " 繁体简体
  "----------------------------------------------------------------------
  xmap <leader>xz :!opencc -c t2s<cr>
  nmap <leader>xz :%!opencc -c t2s<cr>
  xmap <leader>xZ :!opencc -c s2t<cr>
  nmap <leader>xZ :%!opencc -c s2t<cr>

  "----------------------------------------------------------------------
  " base64
  "----------------------------------------------------------------------
  xmap <silent> <leader>xB :<c-u>call base64#v_atob()<cr>
  xmap <silent> <leader>xb :<c-u>call base64#v_btoa()<cr>

  "----------------------------------------------------------------------
  " unicode escape
  "----------------------------------------------------------------------
  xmap <silent> <leader>xu :<c-u>call visual#replace_by_fn("UnicodeEscapeString")<cr>
  xmap <silent> <leader>xU :<c-u>call visual#replace_by_fn("UnicodeUnescapeString")<cr>

  "----------------------------------------------------------------------
  " text escape
  "----------------------------------------------------------------------
  xmap <silent> <leader>xs :<c-u>call visual#replace_by_fn("EscapeText")<cr>
  " xmap <silent> <leader>xU :<c-u>call visual#replace_by_fn("UnicodeUnescapeString")<cr>

  "----------------------------------------------------------------------
  " url encode
  "----------------------------------------------------------------------
  nmap <leader>xh :%!python -c 'import sys,urllib;print urllib.quote(sys.stdin.read().strip())'<cr>
  nmap <leader>xH :%!python -c 'import sys,urllib;print urllib.unquote(sys.stdin.read().strip())'<cr>

  xmap <silent> <leader>cc <Plug>(coc-codeaction-selected)<cr>
  nmap <silent> <leader>cc <Plug>(coc-codeaction-selected)<cr>

  xmap <leader>xh :!python -c 'import sys,urllib;print urllib.quote(sys.stdin.read().strip())'<cr>
  xmap <leader>xH :!python -c 'import sys,urllib;print urllib.unquote(sys.stdin.read().strip())'<cr>

  " ugly hack to start newline and keep indent
  nnoremap <silent> o o<space><bs>
  nnoremap <silent> O O<space><bs>
  inoremap <silent> <cr> <cr><space><bs>

  "----------------------------------------------------------------------
  " command line map
  "----------------------------------------------------------------------
  cmap <c-a> <c-b>
  ]]

end, 0)
