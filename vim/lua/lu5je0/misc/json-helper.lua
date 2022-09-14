local M = {}

M.compress = function()
  vim.cmd(':%!jq -c')
end

M.format = function()
  vim.cmd(':%!jq')
end

M.setup = function()
  vim.api.nvim_create_user_command('JsonCompress', function()
    M.compress()
  end, { force = true })

  vim.api.nvim_create_user_command('JsonFormat', function()
    M.format()
  end, { force = true })
end

return M
