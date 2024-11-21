local keys_helper = require('lu5je0.core.keys')

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

---@diagnostic disable-next-line: param-type-mismatch
vim.schedule(function()
  -- movement
  set_map({ 'x', 'n', 'o' }, 'H', '^')
  set_map({ 'x', 'n', 'o' }, 'L', '$')
  
  --cmdline
  vim.cmd [[
  cnoremap <expr> <up> wildmenumode() ? "\<c-p>" : "\<up>"
  cnoremap <expr> <down> wildmenumode() ? "\<c-n>" : "\<down>"
  ]]
  -- set_map({ 'c' }, '<down>', '<c-n>')
  -- set_map({ 'c' }, '<up>', '<s-tab>')

  -- toggle
  set_n_map('<leader>vn', option_toggler.new_toggle_fn({ 'set nonumber', 'set number' }))
  set_n_map('<leader>vp', option_toggler.new_toggle_fn({ 'set nopaste', 'set paste' }))
  set_n_map('<leader>vm', option_toggler.new_toggle_fn({ 'set mouse=c', 'set mouse=a' }))
  -- set_n_map('<leader>vs', option_toggler.new_toggle_fn({ 'set signcolumn=no', 'set signcolumn=yes:1' }))
  set_n_map('<leader>vl', option_toggler.new_toggle_fn({ 'set cursorline', 'set nocursorline' }))
  set_n_map('<leader>vf', option_toggler.new_toggle_fn({ 'set foldcolumn=auto:1', 'set foldcolumn=0' }))
  set_n_map('<leader>vd', option_toggler.new_toggle_fn({ 'windo difft', 'windo diffo' }))
  set_n_map('<leader>vh', option_toggler.new_toggle_fn({ 'call hexedit#ToggleHexEdit()' }))
  set_n_map('<leader>vc', option_toggler.new_toggle_fn({ 'set noignorecase', 'set ignorecase' }))
  -- set_n_map('<leader>vi', require('lu5je0.misc.im.mac.im').toggle_save_last_ime)
  set_n_map('<leader>vw', function()
    if vim.wo.wrap then
      print("setlocal nowrap")
      vim.wo.wrap = false
      -- del_map({ 'x', 'n' }, { 'j', 'k' }, { buffer = 0, silent = true })
      -- del_map({ 'x', 'n', 'o' }, { 'H', 'L' }, { buffer = 0, silent = true })
      -- del_map({ 'n' }, 'Y', { buffer = 0 })
    else
      print("setlocal wrap")
      vim.wo.wrap = true
      -- local buffer_opts = vim.deepcopy(default_opts)
      -- buffer_opts.buffer = 0
      -- set_map({ 'x', 'n' }, 'j', 'gj', buffer_opts)
      -- set_map({ 'x', 'n' }, 'k', 'gk', buffer_opts)
      -- set_map({ 'x', 'n', 'o' }, 'H', 'g^', buffer_opts)
      -- set_map({ 'x', 'n', 'o' }, 'L', 'g$', buffer_opts)
      -- set_map({ 'n' }, 'Y', 'gyg$', buffer_opts)
    end
  end)
  -- 
  -- set_n_map('<space><', function()
  --   keys_helper.feedkey('`[v`]')
  -- end)
  -- set_n_map('<space>>', function()
  --   
  -- end)

  -- dir
  -- set_n_map('<leader>fp', function() cmd_and_print('cd ~/.local/share/nvim/lazy') end)
  set_n_map('<leader>fs', function() cmd_and_print('cd ~/.dotfiles') end)
  set_n_map('<leader>ft', function() cmd_and_print('cd ~/test') end)
  
  -- selection search
  set_map('x', { '<leader>/', '<space>/' }, '<Esc>/\\%V', {})
  
  
  set_map('n', '<leader>m', function()
    require('lu5je0.ext.language-detect').delect_and_set_filetype()
  end)
  
  -- text
  set_map('n', '<leader>xx', ":%!", {
    nowait = true
  })

  -- lsp
  set_map({ 'n', 'i' }, { '<m-cr>', '<d-cr>' }, '<leader>cc')

  -- ctrl-c 复制
  set_x_map('<C-c>', 'y')
  
  set_map('n', '<space><space>', function()
    -- 保存当前视图状态
    local save = vim.fn.winsaveview()
    -- 选择最后插入的文本
    vim.cmd('normal! `[v`]')
    -- 重新缩进选定文本
    vim.cmd('silent! normal =')
    -- 恢复视图状态
    vim.fn.winrestview(save)
    keys_helper.feedkey('^')
  end)
  
  -- neovim
  -- 修复按u之后，光标闪烁问题
  set_n_map('u', function()
    vim.cmd("redir => output")
    vim.cmd('silent!' .. 'undo')
    vim.cmd('redir END')
    vim.defer_fn(function()
      print(vim.g.output)
    end, 10)
  end)

  vim.cmd [[
  nmap Q <cmd>execute 'normal @' .. reg_recorded()<CR>
  
  inoremap <S-Tab> <C-V><Tab>

  " 缩进后重新选择
  xmap < <gv
  xmap > >gv
  
  " visual模式搜索
  xnoremap / :/\%V
  
  nnoremap <space>< `[v`]<^
  nnoremap <space>> `[v`]>^
  
  nnoremap <space>H H
  nnoremap <space>h H
  nnoremap <space>L L
  nnoremap <space>l L
  
  " xmap : :<c-u>

  imap <M-j> <down>
  imap <M-k> <up>
  imap <M-h> <left>
  imap <M-l> <right>
  
  " fold
  nmap zA za]zA

  "----------------------------------------------------------------------
  " <leader>
  "----------------------------------------------------------------------
  nmap <silent> <leader>tN <cmd>tabnew<cr>
  nmap <silent> <leader>tc <cmd>tabclose<cr>
  nmap <silent> <leader><leader> <c-^>

  "----------------------------------------------------------------------
  " window control
  "----------------------------------------------------------------------
  " 快速切换窗口
  nmap <silent> <c-j> <c-w>j
  nmap <silent> <c-k> <c-w>k
  nmap <silent> <c-h> <c-w>h
  nmap <silent> <c-l> <c-w>l

  nmap <silent> <left> <cmd>bp<cr>
  nmap <silent> <right> <cmd>bn<cr>
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
  onoremap il <cmd>normal! v$o^oh<cr>
  xnoremap il $o^oh

  onoremap ie <cmd>normal! vgg0oG$<cr>
  xnoremap ie gg0oG$

  onoremap ae <cmd>normal! vgg0oG$<cr>
  xnoremap ae gg0oG$

  "----------------------------------------------------------------------
  " visual mode
  "----------------------------------------------------------------------
  xmap <silent> <m-i> <cmd>lua require("lu5je0.ext.terminal").run_select_in_terminal()<cr>

  "----------------------------------------------------------------------
  " other
  "----------------------------------------------------------------------
  " nnoremap * m`<cmd>keepjumps normal! *``<cr>
  nnoremap <silent> * ms:<c-u>let @/='\V\<'.escape(expand('<cword>'), '/\').'\>'<bar>call histadd('/',@/)<bar>set hlsearch<cr>
  xnoremap * m`:keepjumps <C-u>call visual#star_search_set('/')<CR>/<C-R>=@/<CR><CR>``
  nnoremap v m'v
  nnoremap V m'V

  "----------------------------------------------------------------------
  " leader
  "----------------------------------------------------------------------
  nmap <leader>wo <c-w>o

  "----------------------------------------------------------------------
  " 繁体简体
  "----------------------------------------------------------------------
  xmap <leader>xz <cmd>!opencc -c t2s<cr>
  nmap <leader>xz <cmd>%!opencc -c t2s<cr>
  xmap <leader>xZ <cmd>!opencc -c s2t<cr>
  nmap <leader>xZ <cmd>%!opencc -c s2t<cr>

  "----------------------------------------------------------------------
  " unicode escape
  "----------------------------------------------------------------------
  xmap <silent> <leader>xu <cmd>call visual#replace_by_fn("UnicodeEscapeString")<cr>
  xmap <silent> <leader>xU <cmd>call visual#replace_by_fn("UnicodeUnescapeString")<cr>

  " ugly hack to start newline and keep indent
  nnoremap <silent> o o<space><bs>
  nnoremap <silent> O O<space><bs>
  inoremap <silent> <cr> <cr><space><bs>

  "----------------------------------------------------------------------
  " command line map
  "----------------------------------------------------------------------
  cmap <c-a> <c-b>
  
  " remove default mapppings
  silent! vunmap crr
  ]]

end)
