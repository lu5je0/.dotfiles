vim.api.nvim_add_user_command('CronParser', function(t)
  require('misc/cron-parser').parse_line(t.fargs[1])
end, { force = true, nargs='*' })

vim.api.nvim_add_user_command('CurlConvert', function()
  require("misc/curlconverter").convert()
end, { force = true })

-- json-helper
vim.api.nvim_add_user_command('JsonCompress', function()
  require('misc.json-helper').compress()
end, { force = true })

vim.api.nvim_add_user_command('JsonFormat', function()
  require('misc.json-helper').format()
end, { force = true })
