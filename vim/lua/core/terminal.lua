local M = {}

M.sendToTerminal = function(cmd)
  local v_cmd = "TermExec cmd='%s' go_back=0"
  v_cmd = v_cmd:format(cmd)
  vim.cmd(v_cmd)
end

M.runSelectInTerminal = function()
  M.sendToTerminal(vim.fn['visual#visual_selection']())
end

M.setup = function()
  require("toggleterm").setup{
    size = function(term)
      if term.direction == "horizontal" then
        return 18
      elseif term.direction == "vertical" then
        return vim.o.columns * 0.5
      end
    end,
    open_mapping = [[<c-}>]],
    hide_numbers = true, -- hide the number column in toggleterm buffers
    shade_filetypes = {},
    shade_terminals = false,
    start_in_insert = true,
    insert_mappings = true, -- whether or not the open mapping applies in insert mode
    persist_size = true,
    direction = 'float',
    close_on_exit = true, -- close the terminal window when the process exits
    shell = vim.o.shell, -- change the default shell
  }
  vim.cmd[[
  imap <silent> <m-i> <ESC>:ToggleTerm<CR>
  imap <silent> <d-i> <ESC>:ToggleTerm<CR>

  tmap <silent> <m-i> <c-\><c-n>:ToggleTerm<CR>
  tmap <silent> <d-i> <c-\><c-n>:ToggleTerm<CR>
  
  tmap <silent> <c-h> <c-\><c-n><c-w>h
  tmap <silent> <c-l> <c-\><c-n><c-w>l
  tmap <silent> <c-j> <c-\><c-n><c-w>j
  tmap <silent> <c-k> <c-\><c-n><c-w>k
  tmap <silent> <c-q> <c-\><c-n>

  nmap <silent> <m-i> :ToggleTerm<CR>
  nmap <silent> <d-i> :ToggleTerm<CR>
  
  augroup TerminalConfig
    autocmd!
    autocmd TermOpen * setlocal signcolumn=no
  augroup END
  ]]
end

return M
