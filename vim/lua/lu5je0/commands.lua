vim.api.nvim_create_user_command('CronParser', function(t)
  require('lu5je0.misc.cron-parser').parse_line(t.fargs[1])
end, { force = true, nargs = '*' })

vim.api.nvim_create_user_command('CurlConvert', function()
  require('lu5je0.misc.curlconverter').convert()
end, { force = true })

-- json-helper
vim.api.nvim_create_user_command('JsonCompress', function()
  require('lu5je0.misc.json-helper').compress()
end, { force = true })

vim.api.nvim_create_user_command('JsonFormat', function()
  require('lu5je0.misc.json-helper').format()
end, { force = true })

-- base-64
vim.api.nvim_create_user_command('Base64Encode', function()
  require('lu5je0.misc.base64').encode_buffer()
end, { force = true })

vim.api.nvim_create_user_command('Base64Decode', function()
  require('lu5je0.misc.base64').decode_buffer()
end, { force = true })
