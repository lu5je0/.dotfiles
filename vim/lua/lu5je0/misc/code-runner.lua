---@diagnostic disable: missing-parameter

local M = {}
local expand = vim.fn.expand

local function build_cmd_with_file(cmd)
  return cmd .. ' ' .. ('"%s"'):format(expand('%:p'))
end

local function execute_in_terminal(cmd, append_cmd)
  vim.api.nvim_command('silent write')
  if append_cmd ~= nil then
    cmd = cmd .. ' && ' .. append_cmd
  end
  require("lu5je0.ext.terminal").send_to_terminal(cmd, { go_back = 0 })
  if vim.bo.buftype == 'terminal' and vim.api.nvim_win_get_config(0).relative == '' then
    vim.defer_fn(function()
      vim.cmd("wincmd p")
      vim.cmd("stopinsert")
    end, 0)
  end
end

function M.stop_running()
  local filetype = vim.bo.filetype
  if filetype == 'markdown' then
    vim.cmd('MarkdownPreviewStop')
  end
end

function M.run_file(debug)
  debug = debug or false
  
  local filetype = vim.bo.filetype

  if vim.bo.modified then
    vim.cmd('w')
    print('save')
  end

  if filetype == 'vim' then
    vim.cmd('so %')
  elseif filetype == 'lua' then
    if vim.g.lua_dev == 1 then
      vim.cmd('luafile %')
    else
      execute_in_terminal(build_cmd_with_file('luajit'))
    end
  elseif filetype == 'c' then
    execute_in_terminal(build_cmd_with_file('gcc'), './a.out && rm ./a.out')
  elseif filetype == 'javascript' then
    execute_in_terminal(build_cmd_with_file('node'))
  elseif filetype == 'go' then
    execute_in_terminal(build_cmd_with_file('go run'))
  elseif filetype == 'sh' then
    execute_in_terminal(build_cmd_with_file('bash'))
  elseif filetype == 'markdown' then
    vim.cmd('MarkdownPreview')
  elseif filetype == 'bash' or filetype == 'zsh' then
    execute_in_terminal(build_cmd_with_file('bash'))
  elseif filetype == 'python' then
    if debug then
      execute_in_terminal(build_cmd_with_file('python3 -m debugpy --listen localhost:8086 --wait-for-client'))
    else
      execute_in_terminal(build_cmd_with_file('python3'))
    end
  elseif filetype == 'rust' then
    execute_in_terminal('cargo run')
  elseif filetype == 'typescript' then
    execute_in_terminal(build_cmd_with_file('bun'))
  elseif filetype == 'javascript' then
    execute_in_terminal(build_cmd_with_file('node'))
  elseif filetype == 'java' then
    execute_in_terminal(build_cmd_with_file('java'))
  end
end

function M.key_mapping()
  local opts = {
    noremap = true,
    silent = false,
    desc = 'runner.lua'
  }
  vim.keymap.set('n', '<leader>rr', function()
    M.run_file()
  end, opts)
  
  vim.keymap.set('n', '<leader>rx', function()
    M.stop_running()
  end, opts)
  
  vim.keymap.set('n', '<leader>rd', function()
    M.run_file(true)
    
    vim.defer_fn(function()
      require("dap").continue()
    end, 200)
  end, opts)
end

function M.create_command()
  vim.api.nvim_create_user_command('RunFile', function()
    M.run_file()
  end, { force = true, nargs = '*' })

  vim.g.lua_dev = 1
  vim.cmd [[
  command! -nargs=0 LuaDevOn let g:lua_dev=1
  command! -nargs=0 LuaDevOff let g:lua_dev=0
  ]]
end

return M
