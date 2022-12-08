vim.g.mapleader = ','

-- option toggle
local option_toggler = require('lu5je0.misc.option-toggler')
local default_opts = { desc = 'mappings.lua', silent = true }

local function del_map(modes, lhs, opts)
  if type(lhs) == 'table' then
    for _, v in ipairs(lhs) do
      pcall(vim.keymap.del, modes, v, opts)
    end
  else
    pcall(vim.keymap.del, modes, lhs, opts)
  end
end

local function set_map(modes, lhs, rhs, opts)
  if opts == nil then
    opts = default_opts
  end

  if type(lhs) == 'table' then
    for _, v in ipairs(lhs) do
      vim.keymap.set(modes, v, rhs, opts)
    end
  else
    vim.keymap.set(modes, lhs, rhs, opts)
  end
end

local set_n_map = function(...) set_map('n', ...) end
local set_x_map = function(...) set_map('x', ...) end

local cmd_and_print = function(...)
  vim.cmd(...)
  print(...)
end

vim.defer_fn(function()
  -- movement
  set_map({ 'x', 'n', 'o' }, 'H', '^')
  set_map({ 'x', 'n', 'o' }, 'L', '$')

  -- toggle
  set_n_map('<leader>vn', option_toggler.new_toggle_fn({ 'set nonumber', 'set number' }))
  set_n_map('<leader>vp', option_toggler.new_toggle_fn({ 'set nopaste', 'set paste' }))
  set_n_map('<leader>vm', option_toggler.new_toggle_fn({ 'set mouse=c', 'set mouse=a' }))
  set_n_map('<leader>vs', option_toggler.new_toggle_fn({ 'set signcolumn=no', 'set signcolumn=yes:1' }))
  set_n_map('<leader>vl', option_toggler.new_toggle_fn({ 'set cursorline', 'set nocursorline' }))
  set_n_map('<leader>vf', option_toggler.new_toggle_fn({ 'set foldcolumn=auto:9', 'set foldcolumn=0' }))
  set_n_map('<leader>vd', option_toggler.new_toggle_fn({ 'windo difft', 'windo diffo' }))
  set_n_map('<leader>vh', option_toggler.new_toggle_fn({ 'call hexedit#ToggleHexEdit()' }))
  set_n_map('<leader>vc', option_toggler.new_toggle_fn({ 'set noignorecase', 'set ignorecase' }))
  -- set_n_map('<leader>vi', require('lu5je0.misc.im.mac.im').toggle_save_last_ime)
  set_n_map('<leader>vw', function()
    if vim.wo.wrap then
      print("setlocal nowrap")
      vim.wo.wrap = false
      del_map({ 'x', 'n' }, { 'j', 'k' }, { buffer = 0, silent = true })
      del_map({ 'x', 'n', 'o' }, { 'H', 'L' }, { buffer = 0, silent = true })
      -- del_map({ 'n' }, 'Y', { buffer = 0 })
    else
      print("setlocal wrap")
      vim.wo.wrap = true
      local buffer_opts = vim.deepcopy(default_opts)
      buffer_opts.buffer = 0
      set_map({ 'x', 'n' }, 'j', 'gj', buffer_opts)
      set_map({ 'x', 'n' }, 'k', 'gk', buffer_opts)
      set_map({ 'x', 'n', 'o' }, 'H', 'g^', buffer_opts)
      set_map({ 'x', 'n', 'o' }, 'L', 'g$', buffer_opts)
      -- set_map({ 'n' }, 'Y', 'gyg$', buffer_opts)
    end
  end)
  
  -- dir
  set_n_map('<leader>fp', function() cmd_and_print('cd ~/.local/share/nvim/site/pack/packer') end)
  set_n_map('<leader>fd', function() cmd_and_print(':cd ~/.dotfiles') end)
  set_n_map('<leader>ft', function() cmd_and_print(':cd ~/test') end)

  -- lsp
  set_map({ 'n', 'i' }, { '<m-cr>', '<d-cr>' }, '<leader>cc')

  -- ctrl-c 复制
  set_x_map('<C-c>', 'y')

  vim.cmd [[
  nmap Q <cmd>execute 'normal @' .. reg_recorded()<CR>

  " 缩进后重新选择
  xmap < <gv
  xmap > >gv
  
  " xmap : :<c-u>

  imap <M-j> <down>
  imap <M-k> <up>
  imap <M-h> <left>
  imap <M-l> <right>

  "----------------------------------------------------------------------
  " <leader>
  "----------------------------------------------------------------------
  nmap <silent> <leader>tN :tabnew<cr>

  "----------------------------------------------------------------------
  " window control
  "----------------------------------------------------------------------
  " 快速切换窗口
  nmap <silent> <c-j> <c-w>j
  nmap <silent> <c-k> <c-w>k
  nmap <silent> <c-h> <c-w>h
  nmap <silent> <c-l> <c-w>l

  nmap <silent> <left> :bp<cr>
  nmap <silent> <right> :bn<cr>
  nmap <silent> <c-b>o <c-w>p
  nmap <silent> <c-b><c-o> <c-w>p
  
  nnoremap <s-up> <c-w>+
  nnoremap <s-down> <c-w>-
  nnoremap <s-right> <c-w>>
  nnoremap <s-left> <c-w><

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

  "----------------------------------------------------------------------
  " 繁体简体
  "----------------------------------------------------------------------
  xmap <leader>xz :!opencc -c t2s<cr>
  nmap <leader>xz :%!opencc -c t2s<cr>
  xmap <leader>xZ :!opencc -c s2t<cr>
  nmap <leader>xZ :%!opencc -c s2t<cr>

  "----------------------------------------------------------------------
  " unicode escape
  "----------------------------------------------------------------------
  xmap <silent> <leader>xu :<c-u>call visual#replace_by_fn("UnicodeEscapeString")<cr>
  xmap <silent> <leader>xU :<c-u>call visual#replace_by_fn("UnicodeUnescapeString")<cr>

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
