local M = {}

M.send_to_terminal = function(cmd, opts)
  if opts == nil then
    opts = {}
    opts.go_back = 0
  end

  local v_cmd = "TermExec cmd='%s' go_back=" .. opts.go_back
  v_cmd = v_cmd:format(cmd)
  vim.cmd(v_cmd)
end

M.direction = 'horizontal'

M.toggle = function()
  vim.cmd('ToggleTerm direction=' .. M.direction)
end

M.change_terminal_direction = function(direction)
  M.direction = direction
  M.toggle()
end

M.run_select_in_terminal = function()
  M.send_to_terminal(vim.fn['visual#visual_selection']())
end

local function save_terminal_mode()
  vim.cmd([[
  autocmd TermOpen * startinsert
  autocmd TermEnter * let g:terminal_mode='i'
  autocmd BufEnter * if (&buftype ==# 'terminal' && get(g:, 'terminal_mode', 'i') == 'i') | startinsert! | endif
  ]])
end

M.setup = function()
  save_terminal_mode()
  require('toggleterm').setup {
    size = function(term)
      if term.direction == 'horizontal' then
        return 18
      elseif term.direction == 'vertical' then
        return vim.o.columns * 0.4
      end
    end,
    open_mapping = [[<c-}>]],
    hide_numbers = true, -- hide the number column in toggleterm buffers
    shade_filetypes = {},
    shade_terminals = false,
    start_in_insert = false,
    insert_mappings = true, -- whether or not the open mapping applies in insert mode
    persist_size = true,
    direction = M.direction,
    close_on_exit = true, -- close the terminal window when the process exits
    shell = vim.o.shell, -- change the default shell
  }
  vim.cmd([[
  imap <silent> <m-i> <ESC>:lua require('core.terminal').toggle()<CR>
  imap <silent> <d-i> <ESC>:lua require('core.terminal').toggle()<CR>

  tmap <silent> <m-i> <c-\><c-n>:lua require('core.terminal').toggle()<CR>
  tmap <silent> <d-i> <c-\><c-n>:lua require('core.terminal').toggle()<CR>
  
  nmap <silent> <m-i> :lua require('core.terminal').toggle()<CR>
  nmap <silent> <d-i> :lua require('core.terminal').toggle()<CR>
  
  tmap <silent> <c-w>L <c-\><c-n><m-i>:lua require('core.terminal').change_terminal_direction('vertical')<CR>
  tmap <silent> <c-w>J <c-\><c-n><m-i>:lua require('core.terminal').change_terminal_direction('horizontal')<CR>
  tmap <silent> <c-w>F <c-\><c-n><m-i>:lua require('core.terminal').change_terminal_direction('float')<CR>
  
  tmap <silent> <c-h> <c-\><c-n><c-w>h
  tmap <silent> <c-l> <c-\><c-n><c-w>l
  tmap <silent> <c-j> <c-\><c-n><c-w>j
  tmap <silent> <c-k> <c-\><c-n><c-w>k
  tmap <silent> <c-q> <c-\><c-n>:let g:terminal_mode='n'<cr>
  
  augroup TerminalConfig
    autocmd!
    autocmd TermOpen * setlocal signcolumn=no
  augroup END
  ]])
end

return M
