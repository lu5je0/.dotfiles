local M = {}


local env_keeper = require('lu5je0.misc.env-keeper').keeper({ terminal_direction = 'float' })
local visual_utils = require('lu5je0.core.visual')

function M.send_to_terminal(cmd, opts)
  require('lu5je0.ext.plugins_helper').load_plugin('toggleterm.nvim')
  
  if opts == nil then
    opts = {
      go_back = 0
    }
  end

  local v_cmd = "TermExec cmd='%s' go_back=" .. opts.go_back .. ' direction=' .. env_keeper.terminal_direction
  v_cmd = v_cmd:format(cmd)
  vim.cmd(v_cmd)
end

function M.toggle()
  vim.cmd('ToggleTerm direction=' .. env_keeper.terminal_direction)
end

function M.change_terminal_direction(direction)
  env_keeper.terminal_direction = direction
  M.toggle()
end

function M.run_select_in_terminal()
  M.send_to_terminal(visual_utils.get_visual_selection_as_string())
end

local function keep_terminal_mode()
  local group = vim.api.nvim_create_augroup('keep_terminal_mode', { clear = true })
  
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    pattern = '*',
    callback = function()
      if vim.bo.buftype == 'terminal' then
        if vim.g.terminal_mode == 'i' then
          vim.cmd('startinsert')
        end
      end
    end,
  })
  
  vim.api.nvim_create_autocmd('TermOpen', {
    group = group,
    pattern = '*',
    callback = function()
      vim.g.terminal_mode = 'i'
      vim.cmd('startinsert')
    end,
  })
end

function M.setup()
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
    direction = env_keeper.terminal_direction,
    close_on_exit = true, -- close the terminal window when the process exits
    shell = vim.o.shell, -- change the default shell
    -- winbar = {
    --   enabled = true,
    --   name_formatter = function(term) --  term: Terminal
    --     return term.name
    --   end
    -- },
  }
  vim.cmd([[
  imap <silent> <m-i> <ESC>:lua require('lu5je0.ext.terminal').toggle()<CR>
  imap <silent> <d-i> <ESC>:lua require('lu5je0.ext.terminal').toggle()<CR>

  nmap <silent> <m-i> :lua require('lu5je0.ext.terminal').toggle()<CR>
  nmap <silent> <d-i> :lua require('lu5je0.ext.terminal').toggle()<CR>
  
  tmap <silent> <c-w>L <c-\><c-n><m-i>:lua require('lu5je0.ext.terminal').change_terminal_direction('vertical')<CR>
  tmap <silent> <c-w>J <c-\><c-n><m-i>:lua require('lu5je0.ext.terminal').change_terminal_direction('horizontal')<CR>
  tmap <silent> <c-w>F <c-\><c-n><m-i>:lua require('lu5je0.ext.terminal').change_terminal_direction('float')<CR>
  
  
  tmap <silent> <m-i> <c-\><c-n>:lua require('lu5je0.ext.terminal').toggle()<CR>:let g:terminal_mode='i'<cr>
  tmap <silent> <d-i> <c-\><c-n>:lua require('lu5je0.ext.terminal').toggle()<CR>:let g:terminal_mode='i'<cr>
  tmap <silent> <c-h> <c-\><c-n><c-w>h:let g:terminal_mode='i'<cr>
  tmap <silent> <c-l> <c-\><c-n><c-w>l:let g:terminal_mode='i'<cr>
  tmap <silent> <c-j> <c-\><c-n><c-w>j:let g:terminal_mode='i'<cr>
  tmap <silent> <c-k> <c-\><c-n><c-w>k:let g:terminal_mode='i'<cr>
  tmap <silent> <c-q> <c-\><c-n>:let g:terminal_mode='n'<cr>
  ]])
  
  keep_terminal_mode()
end

return M
