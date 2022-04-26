local M = {}

local function build_cmd_with_file(cmd)
  return cmd .. ' ' .. vim.fn.expand('%:p')
end

local function execute_in_terminal(cmd, append_cmd)
  vim.api.nvim_command('silent write')
  if append_cmd ~= nil then
    cmd = cmd .. ' && ' .. append_cmd
  end
  require("lu5je0.ext.terminal").send_to_terminal(cmd, { go_back = 1 })
end

local function special()
  local fullpath = vim.fn.expand("%:p")
  if vim.bo.filetype == 'lua' and fullpath == '/home/lu5je0/.dotfiles/wezterm/wezterm.lua' and vim.fn.has('wsl') == 1 then
    vim.api.nvim_command('silent write')
    vim.fn.system('cp ' .. fullpath .. ' ' .. '/mnt/d/Program\\ Files/WezTerm/wezterm.lua')
    print("copied to windows")
    return true
  end
  return false
end

M.run_file = function()
  local filetype = vim.bo.filetype
  if filetype == 'vim' then
    vim.cmd('w | so %')
  elseif filetype == 'lua' then
    if special() then
      return
    end
    if vim.g.lua_dev == 1 then
      vim.cmd [[
      w
      luafile %
      " let file = expand('%')
      " vnew | pu=execute('luafile ' . file)
      ]]
    else
      execute_in_terminal(build_cmd_with_file('luajit'))
    end
  elseif filetype == 'c' then
    execute_in_terminal(build_cmd_with_file('gcc'), './a.out && rm ./a.out')
  elseif filetype == 'javascript' then
    execute_in_terminal(build_cmd_with_file('node'))
  elseif filetype == 'go' then
    execute_in_terminal(build_cmd_with_file('go run'))
  elseif filetype == 'markdown' then
    vim.cmd('MarkdownPreview')
  elseif filetype == 'bash' or filetype == 'zsh' then
    execute_in_terminal(build_cmd_with_file('bash'))
  elseif filetype == 'python' then
    execute_in_terminal(build_cmd_with_file('python3'))
  elseif filetype == 'rust' then
    execute_in_terminal('cargo run')
  elseif filetype == 'java' then
    execute_in_terminal(build_cmd_with_file('java'))
  end
end

M.key_mapping = function()
  local opts = {
    noremap = true,
    silent = true,
    desc = 'runner.lua'
  }
  vim.keymap.set('n', '<leader>rr', function()
    M.run_file()
  end, opts)
end

M.command = function()
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
