local M = {}

M.compress = function()
  vim.cmd(':%!jq -c')
end

M.format = function()
  vim.cmd(':%!jq')
end

M.jq = function (args)
  vim.cmd(':%!jq ' .. args)
end

M.setup = function()
  vim.api.nvim_create_user_command('JsonCompress', function()
    M.compress()
  end, { force = true })

  vim.api.nvim_create_user_command('JsonFormat', function()
    M.format()
  end, { force = true })
  
  vim.api.nvim_create_user_command('Json', function()
    vim.cmd('set ft=json')
    M.format()
  end, { force = true })
  
  vim.api.nvim_create_user_command('Jq', function(args)
    M.jq(args.args)
  end, { force = true, nargs = '*' })
end

return M
