vim.api.nvim_create_user_command('CronParser', function(t)
  require('lu5je0.misc.cron-parser').parse_line(t.fargs[1])
end, { force = true, nargs = '*' })

vim.api.nvim_create_user_command('CurlConvert', function()
  require('lu5je0.misc.curlconverter').convert()
end, { force = true })

vim.api.nvim_create_user_command('ReloadAsEncoding', function(t)
  vim.cmd('e ++enc=' .. t.fargs[1])
end, { force = true, nargs = 1, complete = function()
  return { 'utf8', 'gbk', 'gb2312', 'gb18030', 'utf16' }
end })

require('lu5je0.misc.code-runner').command()
