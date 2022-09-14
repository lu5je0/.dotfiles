vim.api.nvim_create_user_command('CronParser', function(t)
  require('lu5je0.misc.cron-parser').parse_line(t.fargs[1])
end, { force = true, nargs = '*' })

vim.api.nvim_create_user_command('CurlConvert', function()
  require('lu5je0.misc.curlconverter').convert()
end, { force = true })

require('lu5je0.misc.code-runner').command()
