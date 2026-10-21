local M = {}

function M.open_path(path, opts)
  path = vim.fn.expand(path)
  vim.cmd('cd ' .. vim.fn.fnameescape(path))
  require('lu5je0.ext.sidebar').open_tab(require('lu5je0.ext.sidebar.config').tab_idx('files'), {
    no_toggle = true,
    focus = false,
  })
  if opts and opts.print_path then
    print('cd ' .. path)
  end
end

-- Registered after Sidebar setup; ext.loader supplies the first-use command proxies.
function M.setup()
  vim.api.nvim_create_user_command('Plugins', function()
    M.open_path(vim.fn.stdpath('data') .. '/lazy', { print_path = true })
  end, { force = true })

  vim.api.nvim_create_user_command('SwapFiles', function()
    M.open_path(vim.fn.stdpath('state') .. '/swap', { print_path = true })
  end, { force = true })

  vim.api.nvim_create_user_command('TimeMachine', function()
    M.open_path(require('lu5je0.misc.time-machine').get_path(), { print_path = true })
  end, { force = true })
end

return M
